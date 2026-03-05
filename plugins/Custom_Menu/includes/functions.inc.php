<?php
/**
 * Plugin functions
 *
 * @package Custom Menu plugin
 */

/**
 * Output list of modules (for drag and drop)
 * Only displays modules with top level menu entry
 * Deactivated modules are striked-through
 *
 * Depends on plugins/Custom_Menu/js/dragdrop.js being loaded separately
 *
 * @global $RosarioModules
 * @global $RosarioCoreModules
 */
function CustomMenuModulesListOutput()
{
	global $RosarioModules,
		$RosarioCoreModules;

	$menu = [];

	// include Menu.php for each module
	foreach ( (array) $RosarioModules as $module => $active )
	{
		if ( ROSARIO_DEBUG )
		{
			include 'modules/' . $module . '/Menu.php';
		}
		else
		{
			@include 'modules/' . $module . '/Menu.php';
		}
	}

	echo '<div id="dropbox" style="padding: 8px; border: 4px dashed #ddd">';

	foreach ( (array) $menu as $modcat => $profiles )
	{
		$values = isset( $profiles['admin'] ) ? $profiles['admin'] : [];

		if ( empty( $values ) )
		{
			// Do not display empty module (no programs allowed).
			continue;
		}

		if ( isset( $values['title'] ) )
		{
			$module_title = $values['title'];
		}
		elseif ( ! in_array( $modcat, $RosarioCoreModules ) )
		{
			$module_title = dgettext( $modcat, str_replace( '_', ' ', $modcat ) );
		}
		else
		{
			$module_title = _( str_replace( '_', ' ', $modcat ) );
		}

		$inactive_css = $RosarioModules[ $modcat ] ? '' : ' text-decoration: line-through;';

		echo '<h3 class="dashboard-module-title" draggable="true"
			style="cursor: move; margin: 0; padding: 4px 0;' . $inactive_css . '" id="custom_menu_' . $modcat . '">
			<input type="hidden" name="modules[]" value="' . $modcat . '" />
			<span class="module-icon ' . $modcat . '"';

		if ( ! in_array( $modcat, $RosarioCoreModules ) )
		{
			// Modcat is addon module, set custom module icon.
			echo ' style="background-image: url(modules/' . $modcat . '/icon.png);"';
		}

		echo '></span> ' . $module_title . '</h3>';
	}

	echo '</div>';
}

/**
 * Get ordered modules
 *
 * @global $RosarioModules
 *
 * @param array $modules Ordered modules, only contains modules with top level menu entry
 *
 * @return array Ordered modules, contains all modules.
 */
function CustomMenuOrderedModules( $modules )
{
	global $RosarioModules;

	$ordered_modules = [];

	foreach ( $modules as $module )
	{
		if ( ! isset( $RosarioModules[ $module ] ) )
		{
			continue;
		}

		$ordered_modules[ $module ] = $RosarioModules[ $module ];
	}

	foreach ( $RosarioModules as $module => $active )
	{
		if ( ! isset( $ordered_modules[ $module ] ) )
		{
			$ordered_modules[ $module ] = $active;
		}
	}

	return $ordered_modules;
}
