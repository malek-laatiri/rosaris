<?php
/**
 * Send Notification to Users
 */

if ( ! function_exists( 'SendNotificationNewUserAccount' ) )
{
	/**
	 * Send New User Account notification
	 * Do not send notification if password not set or "No Access" profile.
	 * Send notification even if RosarioSIS installed on localhost (Windows typically)
	 * because action should originate in user choice (checkbox checked).
	 *
	 * @since 6.1
	 *
	 * @uses _rosarioLoginURL() function
	 *
	 * @param int    $staff_id User ID.
	 * @param string $to       To email address. Defaults to user email.
	 * @param string $password Plain password.
	 *
	 * @return bool  False if email not sent, else true.
	 */
	function SendNotificationNewUserAccount( $staff_id, $to = '', $password = '' )
	{
		require_once 'ProgramFunctions/SendEmail.fnc.php';

		if ( empty( $to ) )
		{
			$to = DBGetOne( "SELECT EMAIL FROM staff
				WHERE STAFF_ID='" . (int) $staff_id . "'" );
		}

		if ( ! $staff_id
			|| ! filter_var( $to, FILTER_VALIDATE_EMAIL ) )
		{
			return false;
		}

		$is_no_access_profile = DBGetOne( "SELECT 1 FROM staff
			WHERE STAFF_ID='" . (int) $staff_id . "'
			AND PROFILE='none'" );

		$is_password_set = DBGetOne( "SELECT 1 FROM staff
			WHERE STAFF_ID='" . (int) $staff_id . "'
			AND PASSWORD IS NOT NULL" );

		if ( $is_no_access_profile
			|| ! $is_password_set )
		{
			return false;
		}

		$rosario_url = _rosarioLoginURL();

		$message = _( 'Your account was activated (%d). You can login at %s' );

		$staff_username = DBGetOne( "SELECT USERNAME
			FROM staff
			WHERE STAFF_ID='" . (int) $staff_id . "'" );

		$message .= "\n\n" . _( 'Username' ) . ': ' . $staff_username;

		if ( $password )
		{
			$message .= "\n" . _( 'Password' ) . ': ' . $password;
		}

		$message = sprintf( $message, $staff_id, $rosario_url );

		return SendEmail( $to, _( 'User Account' ), $message );
	}
}

if ( ! function_exists( '_rosarioLoginURL' ) )
{
	/**
	 * RosarioSIS login page URL
	 * Removes part beginning with 'Modules.php' or 'index.php' from URI.
	 *
	 * Local function
	 *
	 * @since 5.9
	 *
	 * @return string Login page URL.
	 */
	function _rosarioLoginURL()
	{
		if ( function_exists( 'RosarioURL' ) )
		{
			return RosarioURL();
		}

		$site_url = 'http://';

		if ( ( isset( $_SERVER['HTTPS'] ) && $_SERVER['HTTPS'] === 'on' )
			|| ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' )
			|| ( isset( $_SERVER['HTTP_X_FORWARDED_SSL'] ) && $_SERVER['HTTP_X_FORWARDED_SSL'] === 'on' ) )
		{
			// Fix detect https inside Docker or behind reverse proxy.
			$site_url = 'https://';
		}

		$site_url .= $_SERVER['SERVER_NAME'];

		if ( $_SERVER['SERVER_PORT'] != '80'
			&& $_SERVER['SERVER_PORT'] != '443' )
		{
			$site_url .= ':' . $_SERVER['SERVER_PORT'];
		}

		$site_url .= dirname( $_SERVER['SCRIPT_NAME'] ) === DIRECTORY_SEPARATOR ?
			// Add trailing slash.
			'/' : dirname( $_SERVER['SCRIPT_NAME'] ) . '/';

		return $site_url;
	}
}
