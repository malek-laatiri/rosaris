<?php
/**
 * Student Import
 *  1. Upload CSV or Excel file
 *  2. Associate CSV columns to Student Fields
 *  3. Import students / addresses (Premium) / contacts (Premium)
 *
 * @package Student Import module
 */

if ( file_exists( 'ProgramFunctions/SendNotification.fnc.php' ) )
{
	require_once 'ProgramFunctions/SendNotification.fnc.php';
}

// @deprecated since 6.1.
require_once 'modules/Students_Import/includes/SendNotifications.fnc.php';

require_once 'ProgramFunctions/FileUpload.fnc.php';

require_once 'modules/Students_Import/includes/StudentsImport.fnc.php';

if ( file_exists( 'modules/School_Setup/includes/Addon.fnc.php' ) )
{
	// @since RosarioSIS 11.4
	require_once 'modules/School_Setup/includes/Addon.fnc.php';

	if ( function_exists( 'AddonUpsellPremium' ) )
	{
		// @since RosarioSIS 12.1
		echo AddonUpsellPremium( 'module', 'Students_Import' );
	}
}

DrawHeader( ProgramTitle() ); // Display main header with Module icon and Program title.

// Upload.
if ( $_REQUEST['modfunc'] === 'upload' )
{
	$error = [];

	if ( ! isset( $_SESSION['StudentsImport.php']['csv_file_path'] )
		|| ! $_SESSION['StudentsImport.php']['csv_file_path'] )
	{
		// Save original file name.
		$_SESSION['StudentsImport.php']['original_file_name'] = issetVal( $_FILES['students-import-file']['name'] );

		// Upload CSV file.
		$students_import_file_path = FileUpload(
			'students-import-file',
			sys_get_temp_dir() . DIRECTORY_SEPARATOR, // Temporary directory.
			[ '.csv', '.xls', '.xlsx' ],
			0,
			$error
		);

		if ( empty( $error ) )
		{
			// Convert Excel files to CSV.
			$csv_file_path = ConvertExcelToCSV( $students_import_file_path );

			// Open file.
			if ( ( fopen( $csv_file_path, 'r' ) ) === false )
			{
				$error[] = dgettext( 'Students_Import', 'Cannot open file.' );
			}
			else
			{
				$_SESSION['StudentsImport.php']['csv_file_path'] = $csv_file_path;
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
	if ( ! isset( $_SESSION['StudentsImport.php']['csv_file_path'] )
		|| fopen( $_SESSION['StudentsImport.php']['csv_file_path'], 'r' ) === false )
	{
		$error[] = dgettext( 'Students_Import', 'Cannot open file.' );
	}
	else
	{
		// Import students.
		$students_imported = CSVImport( $_SESSION['StudentsImport.php']['csv_file_path'] );

		$students_imported_txt = sprintf(
			dgettext( 'Students_Import', '%s students were imported.' ),
			$students_imported
		);

		if ( $students_imported )
		{
			$note[] = button( 'check' ) . '&nbsp;' . $students_imported_txt;
		}
		else
		{
			$warning[] = $students_imported_txt;
		}

		if ( function_exists( 'FileDelete' ) )
		{
			// Security: use FileDelete() instead of unlink()
			FileDelete( $_SESSION['StudentsImport.php']['csv_file_path'], '.csv' );
		}
		else
		{
			// Remove CSV file.
			unlink( $_SESSION['StudentsImport.php']['csv_file_path'] );
		}
	}

	// Unset modfunc & redirect URL.
	RedirectURL( 'modfunc' );

	unset( $_SESSION['StudentsImport.php']['csv_file_path'] );
}

// Display error messages.
echo ErrorMessage( $error, 'error' );

// Display warnings.
echo ErrorMessage( $warning, 'warning' );

// Display note.
echo ErrorMessage( $note, 'note' );


if ( ! $_REQUEST['modfunc'] )
{
	/*if ( isset( $_SESSION['StudentsImport.php']['csv_file_path'] ) )
	{
		// Remove CSV file.
		@unlink( $_SESSION['StudentsImport.php']['csv_file_path'] );*/

		unset( $_SESSION['StudentsImport.php']['csv_file_path'] );
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

	DrawHeader( '<input type="file" name="students-import-file" accept=".csv, application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/vnd.ms-excel" required title="' .
			( function_exists( 'AttrEscape' ) ? AttrEscape( sprintf( _( 'Maximum file size: %01.0fMb' ), FileUploadMaxSize() ) ) : htmlspecialchars( sprintf( _( 'Maximum file size: %01.0fMb' ), FileUploadMaxSize() ), ENT_QUOTES ) ) . '" />
		<span class="loading"></span>
		<br /><span class="legend-red">' . dgettext( 'Students_Import', 'Select CSV or Excel file' ) . '</span>' );

	echo '<br /><div class="center">' . SubmitButton( _( 'Submit' ) ) . '</div>';

	echo '</form>';
}
// Uploaded: show import form!
elseif ( $_REQUEST['modfunc'] === 'upload' )
{
	// Get CSV columns.
	$csv_columns = GetCSVColumns( $_SESSION['StudentsImport.php']['csv_file_path'] );

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

		$rows_number = file( $_SESSION['StudentsImport.php']['csv_file_path'] );

		$rows_number = count( $rows_number );

		DrawHeader(
			$_SESSION['StudentsImport.php']['original_file_name'] . ': ' .
				sprintf( dgettext( 'Students_Import', '%s rows' ), $rows_number ),
			SubmitButton(
				dgettext( 'Students_Import', 'Import Students' ),
				'',
				' class="import-button button-primary"'
			)
		);

		// Hidden input values used by JS below
		?>
		<input type="hidden" disabled id="import_alert_txt" value="<?php echo ( function_exists( 'AttrEscape' ) ?
			AttrEscape( dgettext( 'Students_Import', 'Are you absolutely ready to import students? Make sure you have backed up your database!' ) ) :
			htmlspecialchars( dgettext( 'Students_Import', 'Are you absolutely ready to import students? Make sure you have backed up your database!' ), ENT_QUOTE ) ); ?>" />
		<input type="hidden" disabled id="import_stop_button_html" value="<?php echo ( function_exists( 'AttrEscape' ) ?
			AttrEscape( SubmitButton( dgettext( 'Students_Import', 'Stop' ), '', 'class="stop-button"' ) ) :
			htmlspecialchars( SubmitButton( dgettext( 'Students_Import', 'Stop' ), '', 'class="stop-button"' ), ENT_QUOTE ) ); ?>" />
		<script src="modules/Students_Import/js/ImportFormSubmit.js?v=10.8"></script>
		<?php

		// Import first row? (generally column names).
		DrawHeader( CheckboxInput(
				'',
				'import-first-row',
				dgettext( 'Students_Import', 'Import first row' ),
				'',
				true
			),
			'<a href="' . ( function_exists( 'URLEscape' ) ?
				URLEscape( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=upload' ) :
				_myURLEncode( 'Modules.php?modname=' . $_REQUEST['modname'] . '&modfunc=upload' ) ) . '">' .
				dgettext( 'Students_Import', 'Reset form' ) . '</a>'
		);

		// Premium: Custom date format (update tooltips on change), may be necessary for Japan: YY-MM-DD?
		// Premium: Custom checkbox checked format (update tooltips on change).

		echo '<br /><table class="widefat cellspacing-0 center">';

		/**
		 * Student Fields.
		 */
		echo '<tr><td><h4>' . _( 'Student Fields' ) . '</h4></td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'FIRST_NAME', $csv_columns,  _( 'First Name' ), 'required' ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'MIDDLE_NAME', $csv_columns, _( 'Middle Name' ) ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'LAST_NAME', $csv_columns, _( 'Last Name' ), 'required' ) .
		'</td></tr>';

		$tooltip = _makeFieldTypeTooltip(
			'numeric',
			'; ' . dgettext( 'Students_Import', 'IDs are automatically generated if you select "N/A".' )
		);

		echo '<tr><td>' .
			_makeSelectInput( 'STUDENT_ID', $csv_columns, sprintf( _( '%s ID' ), Config( 'NAME' ) ) . $tooltip ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'USERNAME', $csv_columns, _( 'Username' ) ) .
		'</td></tr>';

		echo '<tr><td>' .
			_makeSelectInput( 'PASSWORD', $csv_columns, _( 'Password' ) ) .
		'</td></tr>';

		/**
		 * Custom Student Fields.
		 */
		$fields_RET = DBGet( "SELECT cf.ID,cf.TITLE,cf.TYPE,cf.SELECT_OPTIONS,
			cf.REQUIRED,cf.CATEGORY_ID,sfc.TITLE AS CATEGORY_TITLE
			FROM custom_fields cf, student_field_categories sfc
			WHERE cf.CATEGORY_ID=sfc.ID
			AND cf.TYPE<>'files'
			ORDER BY sfc.SORT_ORDER IS NULL,sfc.SORT_ORDER,cf.SORT_ORDER IS NULL,cf.SORT_ORDER" );

		$category_id_last = 0;

		foreach ( (array) $fields_RET as $field )
		{
			if ( $category_id_last !== $field['CATEGORY_ID'] )
			{
				// Add Category name as Student Fields separator!
				echo '<tr><td><h4>' . ParseMLField( $field['CATEGORY_TITLE'] ) . '</h4></td></tr>';
			}

			$category_id_last = $field['CATEGORY_ID'];

			$tooltip = _makeFieldTypeTooltip( $field['TYPE'] );

			echo '<tr><td>' .
				_makeSelectInput(
					'CUSTOM_' . $field['ID'],
					$csv_columns,
					ParseMLField( $field['TITLE'] ) . $tooltip,
					$field['REQUIRED'] ? 'required' : ''
				) .
			'</td></tr>';
		}


		/**
		 * Enrollment.
		 */
		echo '<tr><td><h4>' . _( 'Enrollment' ) . '</h4></td></tr>';

		$gradelevels_RET = DBGet( "SELECT ID,TITLE
			FROM school_gradelevels
			WHERE SCHOOL_ID='" . UserSchool() . "'
			ORDER BY SORT_ORDER IS NULL,SORT_ORDER" );

		$options = [];

		foreach ( (array) $gradelevels_RET as $gradelevel )
		{
			// Add 'ID_' prefix not to mix with CSV columns.
			$options[ 'ID_' . $gradelevel['ID'] ] = $gradelevel['TITLE'];
		}

		// Add CSV columns to set Grade Level.
		$options += $csv_columns;

		echo '<tr><td>' .
			_makeSelectInput( 'GRADE_ID', $options, _( 'Grade Level' ), 'required', true ) .
		'</td></tr>';

		$calendars_RET = DBGet( "SELECT CALENDAR_ID,DEFAULT_CALENDAR,TITLE
			FROM attendance_calendars
			WHERE SYEAR='" . UserSyear() . "'
			AND SCHOOL_ID='" . UserSchool() . "'
			ORDER BY DEFAULT_CALENDAR ASC" );

		$options = [];

		foreach ( (array) $calendars_RET as $calendar )
		{
			$options[ $calendar['CALENDAR_ID'] ] = $calendar['TITLE'];

			if ( $calendar['DEFAULT_CALENDAR'] )
			{
				$options[ $calendar['CALENDAR_ID'] ] .= ' (' . _( 'Default' ) . ')';
			}
		}

		$no_chosen = false;

		echo '<tr><td>' .
			_makeSelectInput(
				'CALENDAR_ID',
				$options,
				_( 'Calendar' ),
				'required',
				$no_chosen,
				'enrollment'
			) .
		'</td></tr>';

		$schools_RET = DBGet( "SELECT ID,TITLE
			FROM schools
			WHERE ID!='" . UserSchool() . "'
			AND SYEAR='" . UserSyear() . "'" );

		$options = [
			UserSchool() => _( 'Next grade at current school' ),
			'0' => _( 'Retain' ),
			'-1' => _( 'Do not enroll after this school year' ),
		];

		foreach ( (array) $schools_RET as $school )
		{
			$options[ $school['ID'] ] = $school['TITLE'];
		}

		echo '<tr><td>' .
			_makeSelectInput(
				'NEXT_SCHOOL',
				$options,
				_( 'Rolling / Retention Options' ),
				'required',
				$no_chosen,
				'enrollment'
		) .
		'</td></tr>';

		$enrollment_codes_RET = DBGet( "SELECT ID,TITLE AS TITLE
			FROM student_enrollment_codes
			WHERE SYEAR='" . UserSyear() . "'
			AND TYPE='Add'
			ORDER BY SORT_ORDER IS NULL,SORT_ORDER" );

		$options = [];

		foreach ( (array) $enrollment_codes_RET as $enrollment_code )
		{
			$options[ $enrollment_code['ID'] ] = $enrollment_code['TITLE'];
		}

		echo '<tr><td>' .
			_makeDateInput( 'START_DATE', '', true, 'enrollment' ) . ' -<br />' .
			_makeSelectInput(
				'ENROLLMENT_CODE',
				$options,
				_( 'Attendance Start Date this School Year' )
					. '<div class="tooltip"><i>' .
					dgettext( 'Students_Import', 'If the date is left empty, students will not be enrolled (inactive).' ) .
					'</i></div>',
				'',
				$no_chosen,
				'enrollment'
			) .
		'</td></tr>';

		if ( Config( 'STUDENTS_EMAIL_FIELD' ) )
		{
			$tooltip = '<div class="tooltip"><i>' . dgettext(
				'Students_Import',
				'Notifications are sent if Username, Password, Email Address are set and Attendance Start Date this School Year is on or before today.'
			) . '</i></div>';

			echo '<tr><td>' . CheckboxInput(
				'',
				'send_notification',
				dgettext( 'Students_Import', 'Send email notification to Students' ) . $tooltip,
				'',
				true,
				'Yes',
				'No',
				false,
				'disabled'
			) . '</td></tr>';

			$student_email_field = Config( 'STUDENTS_EMAIL_FIELD' ) === 'USERNAME' ?
				'USERNAME' : 'CUSTOM_' . (int) Config( 'STUDENTS_EMAIL_FIELD' );

			// Enable Send Notification checkbox only if:
			// Username, Password, Email Address set & Attendance Start Date this School Year <= today.
			// Note: hidden inputs are used by JS below
			?>
			<input type="hidden" disabled id="student_email_field" value="<?php echo ( function_exists( 'AttrEscape' ) ?
				AttrEscape( $student_email_field ) :
				htmlspecialchars( $student_email_field, ENT_QUOTE ) ); ?>" />
			<script src="modules/Students_Import/js/SendNotificationEnable.js?v=11.1"></script>
			<?php
		}

		echo '</table>';

		echo '<br /><div class="center">' . SubmitButton(
			dgettext( 'Students_Import', 'Import Students' ),
			'',
			' class="import-button button-primary"'
		) . '</div></form>';
	}
}
