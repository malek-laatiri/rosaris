/**
 * Staff and Parents Import program JS
 * Enable Send Notification checkbox only if:
 * Username, Password, Email Address set & Profile != 'No Access'.
 *
 * @package Staff and Parents Import module
 */

var SendNotificationEnable = function() {
	if ( $('#valuesUSERNAME').val()
		&& $('#valuesPASSWORD').val()
		&& $('#valuesEMAIL').val()
		&& $('#valuesPROFILE').val()
		&& $('#valuesPROFILE').val() !== 'KEY_none' ) {
		$('#send_notification').prop('disabled', false);

		for( i=0; i<3; i++ ) {
			// Highlight effect.
			$('#send_notification').parent('label').fadeTo('slow', 0.5).fadeTo('slow', 1.0);
		}

		return;
	}

	$('#send_notification').prop('disabled', true).prop('checked', false);
};

$(function(){
	$('#valuesUSERNAME,#valuesPASSWORD,#valuesEMAIL,#valuesPROFILE').on('change', SendNotificationEnable);
});
