<?php
/**
 * English Help texts
 *
 * Texts are organized by:
 * - Module
 * - Profile
 *
 * Please use this file as a reference to generate the Gettext [My_Module]_help.po files
 * and translate Help texts to your language.
 * The Catalog should only reference the Help_en.php file
 * and detect the `_help` function / source keyword.
 *
 * @author François Jacquet
 *
 * @package Student Import module
 * @subpackage Help
 */

// STUDENTS IMPORT ---.
if ( User( 'PROFILE' ) === 'admin' ) :
	$help['Students_Import/StudentsImport.php'] = '<p>' . _help( '<i>Student Import</i> allows you to import a student database contained in an <b>Excel</b> spreadsheet or a <b>CSV</b> file.', 'Students_Import' ) . '</p>
	<p>' . _help( 'First thing, it is recommended to <b>backup your database</b> in case something goes wrong.', 'Students_Import' ) . '</p>
	<p>' . _help( 'Then, select the Excel (.xls, .xlsx) or CSV (.csv) file containing your students data using the "Select CSV or Excel file". Then, click the "Submit" button to upload the file. Please note that if you select an Excel file, only the first spreadsheet will be uploaded.', 'Students_Import' ) . '</p>
	<p>' . _help( 'On the next screen, you will be able to associate a column to each Student Field. Also set the Enrollment options that will apply to every student. Please note that the fields in <span style="color:red;">red</span> are mandatory. Check the "Import first row" checkbox at the top of the screen if your file\'s first row contains student data instead of column labels. Please also note that the checked state for fields of the <i>Checkbox</i> type is <i>Y</i>. Once you are set, click the "Import Students" button.', 'Students_Import' ) . '</p>';

endif;
