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
 * @package Staff and Parents Import module
 * @subpackage Help
 */

// STAFF AND PARENTS IMPORT ---.
if ( User( 'PROFILE' ) === 'admin' ) :

	$help['Staff_Parents_Import/StaffParentsImport.php'] = '<p>' . _help( '<i>Staff and Parents Import</i> allows you to import a user database contained in an <b>Excel</b> spreadsheet or a <b>CSV</b> file.', 'Staff_Parents_Import' ) . '</p>
	<p>' . _help( 'First thing, it is recommended to <b>backup your database</b> in case something goes wrong.', 'Staff_Parents_Import' ) . '</p>
	<p>' . _help( 'Then, select the Excel (.xls, .xlsx) or CSV (.csv) file containing your users data using the "Select CSV or Excel file". Then, click the "Submit" button to upload the file. Please note that if you select an Excel file, only the first spreadsheet will be uploaded.', 'Staff_Parents_Import' ) . '</p>
	<p>' . _help( 'On the next screen, you will be able to associate a column to each User Field. Please note that the fields in <span style="color:red;">red</span> are mandatory. Check the "Import first row" checkbox at the top of the screen if your file\'s first row contains user data instead of column labels. Please also note that the checked state for fields of the <i>Checkbox</i> type is <i>Y</i>. Once you are set, click the "Import Users" button.', 'Staff_Parents_Import' ) . '</p>';

endif;
