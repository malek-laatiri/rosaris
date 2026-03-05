<?php
/**
 * Plugin configuration interface
 *
 * @package Custom Menu plugin
 */

require_once 'plugins/Custom_Menu/includes/functions.inc.php';

// Check the script is called by the right program & plugin is activated.
if ( $_REQUEST['modname'] !== 'School_Setup/Configuration.php'
	|| ! $RosarioPlugins['Custom_Menu']
	|| $_REQUEST['modfunc'] !== 'config' )
{
	$error[] = _( 'You\'re not allowed to use this program!' );

	echo ErrorMessage( $error, 'fatal' );
}

// Note: no need to call ProgramTitle() here!

if ( ! empty( $_REQUEST['save'] ) )
{
	if ( ! empty( $_REQUEST['modules'] ) )
	{
		$modules = CustomMenuOrderedModules( $_REQUEST['modules'] );

		if ( $modules )
		{
			$RosarioModules = $modules;

			// @since RosarioSIS 14.0 Prepared SQL statements: no need to escape string
			$modules_save = serialize( $RosarioModules );

			if ( ! function_exists( 'db_query_prep' ) )
			{
				// Maintain backward compatibility.
				$modules_save = DBEscapeString( $modules_save );
			}

			Config( 'MODULES', $modules_save );

			// Reload left menu.
			?>
			<script src="plugins/Custom_Menu/js/ReloadMenu.js?v=1.1"></script>
			<?php

			$note[] = _( 'Done.' );
		}
	}

	// Unset save & redirect URL.
	RedirectURL( 'save' );
}

if ( empty( $_REQUEST['save'] ) )
{
	echo '<form action="' . URLEscape( 'Modules.php?modname=' . $_REQUEST['modname'] .
			'&tab=plugins&modfunc=config&plugin=Custom_Menu&save=true' ) . '" method="POST">';

	echo ErrorMessage( $note, 'note' );

	echo ErrorMessage( $error, 'error' );

	echo '<br />';

	PopTable(
		'header',
		dgettext( 'Custom_Menu', 'Order Modules' )
	);

	CustomMenuModulesListOutput();

	PopTable( 'footer' );

	echo '<br /><div class="center">' . SubmitButton() . '</div>';

	echo '</form>';

	echo '<script src="plugins/Custom_Menu/js/dragdrop.js?v=1.1"></script>';
}
