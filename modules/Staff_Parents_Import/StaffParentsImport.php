<?php
/**
 * Staff and Parents Import
 *  1. Upload CSV or Excel file
 *  2. Associate CSV columns to User Fields
 *  3. Import users
 *
 * @package Staff and Parents Import module
 */

if ( file_exists( 'ProgramFunctions/SendNotification.fnc.php' ) )
{
	require_once 'ProgramFunctions/SendNotification.fnc.php';
}

// @deprecated since 6.1.
require_once 'modules/Staff_Parents_Import/includes/SendNotifications.fnc.php';

require_once 'ProgramFunctions/FileUpload.fnc.php';

require_once 'modules/Staff_Parents_Import/includes/StaffParentsImport.fnc.php';

DrawHeader( ProgramTitle() ); // Display main header with Module icon and Program title.

// Upload.
if ( $_REQUEST['modfunc'] === 'upload' )
{
	$error = [];

	if ( ! isset( $_SESSION['StaffParentsImport.php']['csv_file_path'] )
		|| ! $_SESSION['StaffParentsImport.php']['csv_file_path'] )
	{
		// Save original file name.
		$_SESSION['StaffParentsImport.php']['original_file_name'] = issetVal( $_FILES['users-import-file']['name'] );

		// Upload CSV file.
		$staff_parents_import_file_path = FileUpload(
			'users-import-file',
			sys_get_temp_dir() . DIRECTORY_SEPARATOR, // Temporary directory.
			[ '.csv', '.xls', '.xlsx' ],
			0,
			$error
		);

		if ( empty( $error ) )
		{
			// Convert Excel files to CSV.
			$csv_file_path = ConvertExcelToCSV( $staff_parents_import_file_path );

			// Open file.
			if ( ( fopen( $csv_file_path, 'r' ) ) === false )
			{
				$error[] = dgettext( 'Staff_Parents_Import', 'Cannot open file.' );
			}
			else
			{
				$_SESSION['StaffParentsImport.php']['csv_file_path'] = $csv_file_path;
			}
		}
	}

	if ( $error )
	{
		// Unset modfunc & redirect URL.
		RedirectURL( 'modfunc' );
	}
}
// Import.
elseif ( $_REQUEST['modfunc'] === 'import' )
{
	// Open file.
	if ( ! isset( $_SESSION['StaffParentsImport.php']['csv_file_path'] )
		|| fopen( $_SESSION['StaffParentsImport.php']['csv_file_path'], 'r' ) === false )
	{
		$error[] = dgettext( 'Staff_Parents_Import', 'Cannot open file.' );
	}
	else
	{
		// Import users.
		$staff_parents_imported = CSVImport( $_SESSION['StaffParentsImport.php']['csv_file_path'] );

		$staff_parents_imported_txt = sprintf(
			dgettext( 'Staff_Parents_Import', '%s users were imported.' ),
			$staff_parents_imported
		);

		if ( $staff_parents_imported )
		{
			$note[] = button( 'check' ) . '&nbsp;' . $staff_parents_imported_txt;
		}
		else
		{
			$warning[] = $staff_parents_imported_txt;
		}

		if ( function_exists( 'FileDelete' ) )
		{
			// Security: use FileDelete() instead of unlink()
			FileDelete( $_SESSION['StaffParentsImport.php']['csv_file_path'], '.csv' );
		}
		else
		{
			// Remove CSV file.
			unlink( $_SESSION['StaffParentsImport.php']['csv_file_path'] );
		}
	}

	// Unset modfunc & redirect URL.
	RedirectURL( 'modfunc' );

	unset( $_SESSION['StaffParentsImport.php']['csv_file_path'] );
}

// Display error messages.
echo ErrorMessage( $error, 'error' );

// Display warnings.
echo ErrorMessage( $warning, 'warning' );

// Display note.
echo ErrorMessage( $note, 'note' );


if ( ! $_REQUEST['modfunc'] )
{
	/*if ( isset( $_SESSION['StaffParentsImport.php']['csv_file_path'] ) )
	{
		// Remove CSV file.
		@unlink( $_SESSION['StaffParentsImport.php']['csv_file_path'] );*/

		unset( $_SESSION['StaffParentsImport.php']['csv_file_path'] );
	//}

	// Form.
	echo '<form action="' . ( function_exists( 'URLEscape' ) ?
		URLEscape( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=upload' ) :
		_myURLEncode( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=upload' ) ) . '" method="POST" enctype="multipart/form-data">';

	if ( AllowEdit( 'School_Setup/DatabaseBackup.php' ) )
	{
		DrawHeader( '<a href="Modules.php?modname=School_Setup/DatabaseBackup.php">' .
			_( 'Database Backup' ) . '</a>' );
	}

	DrawHeader( '<input type="file" name="users-import-file" accept=".csv, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/vnd.ms-excel" required title="' .
			( function_exists( 'AttrEscape' ) ? AttrEscape( sprintf( _( 'Maximum file size: %01.0fMb' ), FileUploadMaxSize() ) ) : htmlspecialchars( sprintf( _( 'Maximum file size: %01.0fMb' ), FileUploadMaxSize() ), ENT_QUOTES ) ) . '" />
		<span class="loading"></span>
		<br /><span class="legend-red">' . dgettext( 'Staff_Parents_Import', 'Select CSV or Excel file' ) . '</span>' );

	echo '<br /><div class="center">' . SubmitButton( _( 'Submit' ) ) . '</div>';

	echo '</form>';
}
// Uploaded: show import form!
elseif ( $_REQUEST['modfunc'] === 'upload' )
{
	// Get CSV columns.
	$csv_columns = GetCSVColumns( $_SESSION['StaffParentsImport.php']['csv_file_path'] );

	if ( ! $csv_columns )
	{
		$error = [ 'No columns were found in the uploaded file.' ];

		echo ErrorMessage( $error );
	}
	else
	{
		// Form.
		echo '<form action="' . ( function_exists( 'URLEscape' ) ?
			URLEscape( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=import' ) :
			_myURLEncode( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=import' ) ) . '" method="POST" class="import-form">';

		$rows_number = file( $_SESSION['StaffParentsImport.php']['csv_file_path'] );

		$rows_number = count( $rows_number );

		DrawHeader(
			$_SESSION['StaffParentsImport.php']['original_file_name'] . ': ' .
				sprintf( dgettext( 'Staff_Parents_Import', '%s rows' ), $rows_number ),
			SubmitButton(
				dgettext( 'Staff_Parents_Import', 'Import Users' ),
				'',
				' class="import-button button-primary"'
			)
		);

		// Hidden input values used by JS below
		?>
		<input type="hidden" disabled id="import_alert_txt" value="<?php echo AttrEscape( dgettext(
			'Staff_Parents_Import',
			'Are you absolutely ready to import users? Make sure you have backed up your database!'
		) ); ?>" />
		<input type="hidden" disabled id="import_stop_button_html" value="<?php echo AttrEscape( SubmitButton(
			dgettext( 'Staff_Parents_Import', 'Stop' ),
			'',
			'class="stop-button"'
		) ); ?>" />
		<script src="modules/Staff_Parents_Import/js/ImportFormSubmit.js?v=11.5"></script>
		<?php

		// Import first row? (generally column names).
		DrawHeader( CheckboxInput(
				'',
				'import-first-row',
				dgettext( 'Staff_Parents_Import', 'Import first row' ),
				'',
				true
			),
			'<a href="' . ( function_exists( 'URLEscape' ) ?
				URLEscape( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=upload' ) :
				_myURLEncode( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=upload' ) ) . '">' .
				dgettext( 'Staff_Parents_Import', 'Reset form' ) . '</a>'
		);

		// Premium: Custom date format (update tooltips on change), may be necessary for Japan: YY-MM-DD?
		// Premium: Custom checkbox checked format (update tooltips on change).

		echo '<br /><table class="widefat cellspacing-0 center">';

		/**
		 * User Fields.
		 */
		echo '<tr><td><h4>' . _( 'User Fields' ) . '</h4></td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'FIRST_NAME', $csv_columns,  _( 'First Name' ), 'required' ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'MIDDLE_NAME', $csv_columns, _( 'Middle Name' ) ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'LAST_NAME', $csv_columns, _( 'Last Name' ), 'required' ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'USERNAME', $csv_columns, _( 'Username' ) ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'PASSWORD', $csv_columns, _( 'Password' ) ) .
		'</td></tr>';

		$profile_options = [
			'KEY_admin' => _( 'Administrator' ),
			'KEY_teacher' => _( 'Teacher' ),
			'KEY_parent' => _( 'Parent' ),
			'KEY_none' => _( 'No Access' )
		];

		// Add CSV columns to set Profile.
		$profile_options += $csv_columns;

		echo '<tr><td>' .
			_makeSelectInput( 'PROFILE', $profile_options, _( 'User Profile' ), 'required', true ) .
		'</td></tr>';

		// @since 11.3 Assign Schools
		$i = 0;

		$schools_html = '<table class="cellspacing-0 width-100p"><tr class="st">';

		$schools_RET = DBGet( "SELECT ID,TITLE
			FROM schools
			WHERE SYEAR='" . UserSyear() . "'
			ORDER BY TITLE" );

		foreach ( (array) $schools_RET as $school )
		{
			if ( $i++ % 2 === 0 )
			{
				$schools_html .= '</tr><tr class="st">';
			}

			$schools_html .= '<td>' . CheckboxInput(
				'',
				'schools[' . $school['ID'] . ']',
				$school['TITLE'],
				'',
				true
			) . '&nbsp;</td>';
		}

		$schools_html .= '</tr></table>';

		echo '<tr><td>' .
			$schools_html . FormatInputTitle( _( 'Schools' ), 'schools', false, '' ) .
		'</td></tr>';

		if ( version_compare( ROSARIO_VERSION, '5.9-beta', '<' ) )
		{
			// @since 5.9 Move Email & Phone Staff Fields to custom fields.
			echo '<tr><td>' .
				_makeSelectInput( 'EMAIL', $csv_columns, _( 'Email Address' ) ) .
			'</td></tr>';

			echo '<tr><td>' .
				_makeSelectInput( 'PHONE', $csv_columns, _( 'Phone Number' ) ) .
			'</td></tr>';
		}

		$tooltip = '<div class="tooltip"><i>' . dgettext(
			'Staff_Parents_Import',
			'Notifications are sent if Username, Password, User Profile and Email Address are set.'
		) . '</i></div>';

		echo '<tr><td>' . CheckboxInput(
			'',
			'send_notification',
			dgettext( 'Staff_Parents_Import', 'Send email notification to Users' ) . $tooltip,
			'',
			true,
			'Yes',
			'No',
			false,
			'disabled'
		) . '</td></tr>';

		// Enable Send Notification checkbox only if:
		// Username, Password, Email Address set & Profile != 'No Access'.
		?>
		<script src="modules/Staff_Parents_Import/js/StaffParentsImportEnableSendNotification.js?v=11.5"></script>
		<?php

		/**
		 * Custom User Fields.
		 */
		$fields_RET = DBGet( "SELECT cf.ID,cf.TITLE,cf.TYPE,cf.SELECT_OPTIONS,
			cf.REQUIRED,cf.CATEGORY_ID,sfc.TITLE AS CATEGORY_TITLE
			FROM staff_fields cf,staff_field_categories sfc
			WHERE cf.CATEGORY_ID=sfc.ID
			AND cf.TYPE<>'files'
			ORDER BY sfc.SORT_ORDER IS NULL,sfc.SORT_ORDER,cf.SORT_ORDER IS NULL,cf.SORT_ORDER" );

		$category_id_last = 0;

		foreach ( (array) $fields_RET as $field )
		{
			if ( $category_id_last !== $field['CATEGORY_ID'] )
			{
				// Add Category name as User Fields separator!
				echo '<tr><td><h4>' . ParseMLField( $field['CATEGORY_TITLE'] ) . '</h4></td></tr>';
			}

			$category_id_last = $field['CATEGORY_ID'];

			$tooltip = _makeFieldTypeTooltip( $field['TYPE'] );

			echo '<tr><td>' .
				_makeSelectInput(
					// @since 5.9 Move Email & Phone Staff Fields to custom fields.
					( $field['ID'] === '200000000' ? 'EMAIL' : 'CUSTOM_' . $field['ID'] ),
					$csv_columns,
					ParseMLField( $field['TITLE'] ) . $tooltip,
					$field['REQUIRED'] ? 'required' : ''
				) .
			'</td></tr>';
		}

		echo '</table>';

		echo '<br /><div class="center">' . SubmitButton(
			dgettext( 'Staff_Parents_Import', 'Import Users' ),
			'',
			' class="import-button button-primary"'
		) . '</div></form><br /><br /><br /><br /><br /><br /><br /><br />';
	}
}
