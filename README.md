# Historical Record Recovery Audit

SQL and PowerShell workflow for identifying suspected missing historical records, validating archive existence, and preparing recovered files for QA remediation.

## Overview

This project demonstrates a repeatable framework for investigating historical record gaps by combining:

- SQL-based gap detection
- Archive validation with PowerShell
- Evidence extraction for QA review and remediation

The workflow is designed to help distinguish between:
- true missing records
- indexing or ingest issues
- historically misfiled documents

## Files

- `missing_BkPg.sql` — identifies suspected gaps in historical book/page or instrument-based records
- `Scott_Finder.ps1` — scans archived files, validates likely matches, and isolates documents for review

## Key Capabilities

- Detects suspected missing records using SQL logic
- Applies structured validation rules to reduce false positives
- Scans archived files recursively without relying on assumed year placement
- Matches candidate records against archived filenames
- Prepares verified files for QA and remediation

## Business Impact

- Reduces unnecessary re-requesting of documents
- Improves audit accuracy
- Helps separate true data loss from indexing issues
- Creates a reusable validation framework for future counties or datasets

## Notes

This repository contains sanitized portfolio versions of the scripts. Internal database names, file paths, and environment-specific details have been removed or generalized.
