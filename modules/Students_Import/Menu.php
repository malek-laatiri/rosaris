<?php
/**
 * Menu.php file
 *
 * Required
 * - Add Menu entries to other modules
 *
 * @package Student Import module
 */

// Use dgettext() function instead of _() for Module specific strings translation.
// See locale/README file for more information.
$module_name = dgettext( 'Students_Import', 'Student Import' );

// Add a Menu entry to the Students module.
if ( $RosarioModules['Students'] ) // Verify Students module is activated.
{
	$menu['Students']['admin']['Students_Import/StudentsImport.php'] = dgettext( 'Students_Import', 'Student Import' );
}
