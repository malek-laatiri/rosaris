Student Import module
=====================

![screenshot](https://gitlab.com/francoisjacquet/Students_Import/raw/master/screenshot.png?inline=false)

https://www.rosariosis.org/modules/students-import/

Version 11.1 - August, 2025

Author François Jacquet

License MIT

DESCRIPTION
-----------
Import Students from a CSV or Excel file.
Easily bulk upload your Students database to RosarioSIS.
Import Students info (general & custom fields), enroll them & eventually create accounts.
Optionnally send email notification to Students (if Username, Password, Email Address are set and Attendance Start Date this School Year is on or before today).
This module adds an entry to the Students menu.

Includes Help.
Translated in [French](https://www.rosariosis.org/fr/modules/students-import/), [Spanish](https://www.rosariosis.org/es/modules/students-import/), Bulgarian (thanks to Vanyo Georgiev), Slovenian and Portuguese (Brazil).
[Data processing reference](https://gitlab.com/francoisjacquet/Students_Import/blob/master/DATA_PROCESSING.md).

[**Premium module**](https://www.rosariosis.org/modules/students-import/#premium-module) features:

- Import Addresses & Contacts (Father, Mother, Guardian...) and their information.
- Import Addresses & People custom fields.
- Create Food Service Accounts (and assign a Barcode).
- Generate generic Username & Password so Students can login.
- Update Existing Students info (identify students based on their ID, Username or Name).
- Change the default value ("Y") recognized as checked state: for example, "Yes" (for _Checkbox_ custom fields).
- Create Student in Moodle (if Username and Email Address are set).

CONTENT
-------
Students
- Student Import

INSTALL
-------
Copy the `Students_Import/` folder (if named `Students_Import-master`, rename it) and its content inside the `modules/` folder of RosarioSIS.

Go to _School > Configuration > Modules_ and click "Activate".

Requires RosarioSIS 5.0+
