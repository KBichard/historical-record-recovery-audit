
SET NOCOUNT ON;

 

DECLARE @MaxGapToCount INT = 50;

 

--------------------------------------------------------------------------------

-- CLEANUP

--------------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#CountyEntries')    IS NOT NULL DROP TABLE #CountyEntries;

IF OBJECT_ID('tempdb..#StartAt')          IS NOT NULL DROP TABLE #StartAt;

IF OBJECT_ID('tempdb..#BookBounds')       IS NOT NULL DROP TABLE #BookBounds;

IF OBJECT_ID('tempdb..#AllResults')       IS NOT NULL DROP TABLE #AllResults;

IF OBJECT_ID('tempdb..#Errors')           IS NOT NULL DROP TABLE #Errors;

IF OBJECT_ID('tempdb..#Filtered')         IS NOT NULL DROP TABLE #Filtered;

IF OBJECT_ID('tempdb..#DistinctPages')    IS NOT NULL DROP TABLE #DistinctPages;

IF OBJECT_ID('tempdb..#GlobalAgg')        IS NOT NULL DROP TABLE #GlobalAgg;

IF OBJECT_ID('tempdb..#BooksPresent')     IS NOT NULL DROP TABLE #BooksPresent;

IF OBJECT_ID('tempdb..#MissingBooks')     IS NOT NULL DROP TABLE #MissingBooks;

IF OBJECT_ID('tempdb..#ValidRange')       IS NOT NULL DROP TABLE #ValidRange;

IF OBJECT_ID('tempdb..#OverlapAgg')       IS NOT NULL DROP TABLE #OverlapAgg;

IF OBJECT_ID('tempdb..#MissingPagesAgg')  IS NOT NULL DROP TABLE #MissingPagesAgg;

 

--------------------------------------------------------------------------------

-- METADATA TABLES

--------------------------------------------------------------------------------

CREATE TABLE #CountyEntries

(

    DbName      SYSNAME       NOT NULL,

    Subcode     VARCHAR(20)   NOT NULL,

    [State]     CHAR(2)       NOT NULL,

    CountyName  NVARCHAR(100) NOT NULL,

    PRIMARY KEY CLUSTERED (DbName, Subcode)

);

 

CREATE TABLE #StartAt

(

    Subcode       VARCHAR(20) NOT NULL PRIMARY KEY,

    StartAtNumber BIGINT      NOT NULL

);

 

CREATE TABLE #BookBounds

(

    Subcode VARCHAR(20) NOT NULL PRIMARY KEY,

    MinBook BIGINT NULL,

    MaxBook BIGINT NULL

);

 

CREATE TABLE #AllResults

(

    DatabaseName SYSNAME       NOT NULL,

    Subcode      VARCHAR(20)   NOT NULL,

    [State]      CHAR(2)       NOT NULL,

    CountyName   NVARCHAR(100) NOT NULL,

    TotalRows           BIGINT  NOT NULL,

    MissingBooks        BIGINT  NOT NULL,

    MissingPages_Robust BIGINT  NOT NULL,

    OverlapCount        BIGINT  NOT NULL,

    RangeStart          BIGINT  NULL,

    RangeEnd            BIGINT  NULL

);

 

CREATE TABLE #Errors

(

    DatabaseName SYSNAME        NOT NULL,

    ErrorMessage NVARCHAR(4000) NOT NULL,

    ErrorTime    DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME()

);

 

--------------------------------------------------------------------------------

-- BOOK BOUNDS EXAMPLE (EDIT AS NEEDED)

--------------------------------------------------------------------------------

INSERT INTO #BookBounds (Subcode, MinBook, MaxBook) VALUES

('[CountySubcode]', 1, 999);

 

--------------------------------------------------------------------------------

-- TARGET COUNTIES

--------------------------------------------------------------------------------

INSERT INTO #CountyEntries (DbName, Subcode, [State], CountyName) VALUES

('[SourceDatabase]','KYSCOT','KY',N'Scott');

 

--------------------------------------------------------------------------------

-- CORE ANALYTICS (YOUR FULL ORIGINAL LOGIC)

--------------------------------------------------------------------------------

IF DB_ID(N'[SourceDatabase]') IS NOT NULL

BEGIN

  BEGIN TRY

 

    /* === 1. PARSE KEYS → #Filtered === */

    ;WITH ce AS

    (

      SELECT Subcode, [State], CountyName

      FROM #CountyEntries

      WHERE DbName = N'[SourceDatabase]'

    ),

    Prefixed AS

    (

      SELECT ce.Subcode, K.Key_Key

      FROM [[SourceDatabase]].dbo.ILS_DSM_Keys  AS K

      JOIN [[SourceDatabase]].dbo.ILS_DSM_Files AS F

        ON F.Doc_Id = K.Doc_Id

      JOIN ce

        ON K.Key_Key >= ce.Subcode + ':'

       AND K.Key_Key <  ce.Subcode + ';'

      WHERE F.Version_Type_Cd = 0

    ),

    Parsed AS

    (

      SELECT

          p.Subcode,

          Rest = LTRIM(SUBSTRING(p.Key_Key, LEN(p.Subcode) + 2, 4000))

      FROM Prefixed AS p

    ),

    Split AS

    (

      SELECT

          Subcode,

          Rest,

          DashPos = CHARINDEX('-', Rest)

      FROM Parsed

    ),

    Pieces AS

    (

      SELECT

          s.Subcode,

          s.DashPos,

          BookStr = CASE WHEN s.DashPos > 1 AND s.Rest LIKE '[0-9]%' THEN LEFT(s.Rest, s.DashPos - 1) END,

          PageStr = CASE WHEN s.DashPos > 0 AND LEN(s.Rest) >= s.DashPos + 5 THEN SUBSTRING(s.Rest, s.DashPos + 1, 5) END,

          NextCharAfterPage =

               CASE WHEN s.DashPos > 0 AND LEN(s.Rest) >= s.DashPos + 6 THEN SUBSTRING(s.Rest, s.DashPos + 6, 1) END

      FROM Split AS s

    ),

    Tokens AS

    (

      SELECT

          p.Subcode,

          BookInt = TRY_CONVERT(BIGINT, CASE WHEN p.BookStr IS NOT NULL AND p.BookStr NOT LIKE '%[^0-9]%' THEN p.BookStr END),

          PageInt = TRY_CONVERT(INT,    CASE WHEN p.PageStr LIKE '[0-9][0-9][0-9][0-9][0-9]' THEN p.PageStr END),

          PassesEndGuard =

              CASE WHEN p.DashPos > 0 AND (p.NextCharAfterPage IS NULL OR p.NextCharAfterPage NOT LIKE '[0-9]')

                   THEN 1 ELSE 0 END

      FROM Pieces AS p

    ),

    Filtered_CTE AS

    (

      SELECT

          t.Subcode,

          t.BookInt,

          t.PageInt,

          CombinedInt = CAST(t.BookInt AS BIGINT) * 100000 + t.PageInt

      FROM Tokens AS t

      LEFT JOIN #StartAt    AS sa ON sa.Subcode = t.Subcode

      LEFT JOIN #BookBounds AS bb ON bb.Subcode = t.Subcode

      WHERE t.BookInt IS NOT NULL

        AND t.BookInt > 0

        AND t.PageInt IS NOT NULL

        AND t.PageInt BETWEEN 0 AND 99999

        AND t.PassesEndGuard = 1

        AND (bb.MinBook IS NULL OR t.BookInt >= bb.MinBook)

        AND (bb.MaxBook IS NULL OR t.BookInt <= bb.MaxBook)

        AND (sa.StartAtNumber IS NULL OR (CAST(t.BookInt AS BIGINT) * 100000 + t.PageInt) >= sa.StartAtNumber)

    )

    SELECT *

    INTO #Filtered

    FROM Filtered_CTE;

 

    CREATE CLUSTERED INDEX CX_Filtered_Sub_Book_Page ON #Filtered(Subcode, BookInt, PageInt);

    CREATE NONCLUSTERED INDEX IX_Filtered_Sub_Combined ON #Filtered(Subcode, CombinedInt);

 

    /* === 2. DISTINCT PAGES === */

    SELECT DISTINCT Subcode, BookInt, PageInt

    INTO #DistinctPages

    FROM #Filtered;

 

    CREATE CLUSTERED INDEX CX_DPages_Sub_Book_Page ON #DistinctPages(Subcode, BookInt, PageInt);

 

    /* === 3. AGGREGATES === */

    SELECT

        Subcode,

        TotalRows       = COUNT_BIG(*),

        DistinctNumbers = COUNT(DISTINCT CombinedInt)

    INTO #GlobalAgg

    FROM #Filtered

    GROUP BY Subcode;

    CREATE UNIQUE CLUSTERED INDEX CX_GlobalAgg_Sub ON #GlobalAgg(Subcode);

 

    SELECT

        dp.Subcode,

        PresentBookCount = COUNT(DISTINCT dp.BookInt)

    INTO #BooksPresent

    FROM #DistinctPages AS dp

    GROUP BY dp.Subcode;

    CREATE UNIQUE CLUSTERED INDEX CX_BooksPresent_Sub ON #BooksPresent(Subcode);

 

    SELECT

        ce.Subcode,

        MissingBooks =

          CASE

            WHEN bb.MinBook IS NULL OR bb.MaxBook IS NULL THEN 0

            ELSE (bb.MaxBook - bb.MinBook + 1) - COALESCE(bp.PresentBookCount, 0)

          END

    INTO #MissingBooks

    FROM (SELECT DISTINCT Subcode FROM #CountyEntries WHERE DbName = N'[SourceDatabase]') AS ce

    LEFT JOIN #BookBounds   AS bb ON bb.Subcode = ce.Subcode

    LEFT JOIN #BooksPresent AS bp ON bp.Subcode = ce.Subcode;

    CREATE UNIQUE CLUSTERED INDEX CX_MissingBooks_Sub ON #MissingBooks(Subcode);

 

    SELECT

        Subcode,

        RangeStart = MIN(CAST(BookInt AS BIGINT) * 100000 + PageInt),

        RangeEnd   = MAX(CAST(BookInt AS BIGINT) * 100000 + PageInt)

    INTO #ValidRange

    FROM #DistinctPages

    GROUP BY Subcode;

    CREATE UNIQUE CLUSTERED INDEX CX_ValidRange_Sub ON #ValidRange(Subcode);

 

    SELECT

        ga.Subcode,

        OverlapCount = (ga.TotalRows - ga.DistinctNumbers)

    INTO #OverlapAgg

    FROM #GlobalAgg AS ga;

    CREATE UNIQUE CLUSTERED INDEX CX_OverlapAgg_Sub ON #OverlapAgg(Subcode);

 

    /* === 4. ROBUST MISSING PAGE COUNT === */

    ;WITH Ordered AS

    (

      SELECT

          dp.Subcode,

          dp.BookInt,

          dp.PageInt,

          NextPage = LEAD(dp.PageInt) OVER (PARTITION BY dp.Subcode, dp.BookInt ORDER BY dp.PageInt)

      FROM #DistinctPages dp

    ),

    Gaps AS

    (

      SELECT

          o.Subcode,

          o.BookInt,

          Gap = (o.NextPage - o.PageInt - 1)

      FROM Ordered o

      WHERE o.NextPage IS NOT NULL

        AND o.NextPage > o.PageInt

    ),

    CountableGaps AS

    (

      SELECT Subcode, BookInt, Gap

      FROM Gaps

      WHERE Gap > 0

        AND Gap <= @MaxGapToCount

    )

    SELECT

        cg.Subcode,

        MissingPages_Robust = SUM(cg.Gap)

    INTO #MissingPagesAgg

    FROM CountableGaps cg

    GROUP BY cg.Subcode;

 

    CREATE UNIQUE CLUSTERED INDEX CX_MissingPagesAgg_Sub ON #MissingPagesAgg(Subcode);

 

    /* === FINAL SUMMARY RESULTS === */

    INSERT INTO #AllResults

    (

        DatabaseName, Subcode, [State], CountyName,

        TotalRows, MissingBooks, MissingPages_Robust, OverlapCount,

        RangeStart, RangeEnd

    )

    SELECT

        N'[SourceDatabase]',

        ce.Subcode,

        ce.[State],

        ce.CountyName,

        COALESCE(ga.TotalRows, 0),

        COALESCE(mb.MissingBooks, 0),

        COALESCE(mp.MissingPages_Robust, 0),

        COALESCE(oa.OverlapCount, 0),

        vr.RangeStart,

        vr.RangeEnd

    FROM (SELECT DISTINCT Subcode, [State], CountyName FROM #CountyEntries WHERE DbName = N'[SourceDatabase]') AS ce

    LEFT JOIN #GlobalAgg        AS ga ON ga.Subcode = ce.Subcode

    LEFT JOIN #MissingBooks     AS mb ON mb.Subcode = ce.Subcode

    LEFT JOIN #MissingPagesAgg  AS mp ON mp.Subcode = ce.Subcode

    LEFT JOIN #ValidRange       AS vr ON vr.Subcode = ce.Subcode

    LEFT JOIN #OverlapAgg       AS oa ON oa.Subcode = ce.Subcode;

 

  END TRY

  BEGIN CATCH

    INSERT INTO #Errors (DatabaseName, ErrorMessage)

    VALUES (N'[SourceDatabase]', ERROR_MESSAGE());

  END CATCH

END

ELSE

BEGIN

  INSERT INTO #Errors (DatabaseName, ErrorMessage)

  VALUES (N'[SourceDatabase]', 'Database not found: [SourceDatabase]');

END;

 

--------------------------------------------------------------------------------

-- MAIN SUMMARY OUTPUT

--------------------------------------------------------------------------------

SELECT

    ar.DatabaseName,

    ar.Subcode,

    ar.[State],

    ar.CountyName,

    CASE

        WHEN ar.RangeStart IS NOT NULL THEN

            CONCAT(ar.RangeStart / 100000, '-', RIGHT(CONCAT('00000', ar.RangeStart % 100000), 5))

    END AS RangeStart_BookPage,

    CASE

        WHEN ar.RangeEnd IS NOT NULL THEN

            CONCAT(ar.RangeEnd / 100000, '-', RIGHT(CONCAT('00000', ar.RangeEnd % 100000), 5))

    END AS RangeEnd_BookPage,

    ar.TotalRows,

    ar.MissingBooks,

    ar.MissingPages_Robust,

    ar.OverlapCount

FROM #AllResults ar

ORDER BY ar.Subcode;

 

--------------------------------------------------------------------------------

-- FULL MISSING BOOK LIST

--------------------------------------------------------------------------------

;WITH AllBooks AS

(

    SELECT

        bb.Subcode,

        BookInt = bb.MinBook + v.number

    FROM #BookBounds bb

    JOIN master..spt_values v

      ON v.type = 'P'

     AND v.number BETWEEN 0 AND (bb.MaxBook - bb.MinBook)

)

SELECT

    AllBooks.Subcode,

    AllBooks.BookInt AS MissingBook

FROM AllBooks

LEFT JOIN #DistinctPages dp

       ON dp.Subcode = AllBooks.Subcode

      AND dp.BookInt = AllBooks.BookInt

WHERE dp.BookInt IS NULL

ORDER BY AllBooks.Subcode, AllBooks.BookInt;

 

--------------------------------------------------------------------------------

-- FULL MISSING PAGE LIST (FORMATTED AS DSM KEYS)

--------------------------------------------------------------------------------

;WITH Ordered AS

(

    SELECT

        dp.Subcode,

        dp.BookInt,

        dp.PageInt,

        NextPage = LEAD(dp.PageInt)

                   OVER (PARTITION BY dp.Subcode, dp.BookInt ORDER BY dp.PageInt)

    FROM #DistinctPages dp

),

MissingPages AS

(

    SELECT

        o.Subcode,

        o.BookInt,

        MissingPageInt = o.PageInt + v.number

    FROM Ordered o

    JOIN master..spt_values v

      ON v.type = 'P'

     AND v.number BETWEEN 1 AND (o.NextPage - o.PageInt - 1)

    WHERE o.NextPage IS NOT NULL

)

SELECT

    MissingPages =

        CONCAT(

            Subcode, ':',

            BookInt, '-',

            RIGHT('00000' + CAST(MissingPageInt AS varchar(5)), 5)

        )

FROM MissingPages

ORDER BY

    Subcode,

    BookInt,

    MissingPageInt;