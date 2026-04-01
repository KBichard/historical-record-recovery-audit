# Historical Record Recovery & Validation Framework

SQL and PowerShell workflow for identifying suspected missing historical records, validating archive existence, and preparing recovered files for QA remediation.

---

## Overview

This project demonstrates a real-world data quality and recovery workflow used to investigate missing historical records.

The framework combines:

* SQL-based gap detection
* Archive validation using PowerShell
* Evidence extraction for QA and re-indexing

It is designed to determine whether missing records are:

* Truly missing (data loss)
* Misindexed or improperly ingested
* Present in archival storage but not surfaced in active datasets

---

## Problem

Large-scale historical datasets often contain gaps due to:

* Inconsistent indexing
* Legacy formatting issues
* Ingest or pipeline failures

Without validation, these gaps can lead to:

* Incorrect reporting
* Unnecessary data re-requests
* Reduced confidence in downstream systems

---

## Solution

This framework introduces a repeatable validation process:

1. **Detect suspected gaps using SQL**
2. **Validate existence in archived files using PowerShell**
3. **Match records using structured filename patterns**
4. **Extract confirmed records for QA and remediation**

---

## Files

* `Missing_BkPg.sql`
  Detects missing records using structured key parsing, range validation, and gap detection logic

* `Scott_Finder.ps1`
  Recursively scans archive files, validates matches, and extracts confirmed records

---

## Key Features

* Set-based SQL gap detection across large datasets
* Robust filtering to reduce false positives
* Archive scanning without reliance on assumed directory structure
* Pattern-based matching for record validation
* Automated extraction of verified documents

---

## Business Impact

* Prevents unnecessary document re-requests
* Improves audit accuracy and traceability
* Differentiates true data gaps from indexing issues
* Increases confidence in historical dataset completeness

---

## Notes

This repository contains sanitized portfolio versions of the scripts.
All internal database names, file paths, and environment-specific details have been removed or generalized.
