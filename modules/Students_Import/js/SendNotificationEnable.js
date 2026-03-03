/**
 * Send Notification Enable JS
 *
 * @package Student Import module
 */

// Enable Send Notification checkbox only if:
// Username, Password, Email Address set & Attendance Start Date this School Year <= today.
var sendNotificationEnable = function() {
	var enrollmentDate = $('select[name="year_enrollment[START_DATE]"]').val() + '-' +
		$('select[name="month_enrollment[START_DATE]"]').val() + '-' +
		$('select[name="day_enrollment[START_DATE]"]').val(),
		todayDate = new Date().toISOString().split('T')[0];

	if ( $('#valuesUSERNAME').val()
		&& $('#valuesPASSWORD').val()
		&& $('#values' + $('#student_email_field').val()).val()
		&& enrollmentDate <= todayDate )
	{
		if ( $('#send_notification').prop('disabled') )
		{
			$('#send_notification').prop('disabled', false);

			for( i=0; i<3; i++ ) {
				// Highlight effect.
				$('#send_notification').parent('label').fadeTo('slow', 0.5).fadeTo('slow', 1.0);
			}
		}

		return;
	}

	$('#send_notification').prop('disabled', true).prop('checked', false);
};

$(function() {
	$('#valuesUSERNAME,#valuesPASSWORD').on('change', sendNotificationEnable);
	$('#values' + $('#student_email_field').val()).on('change', sendNotificationEnable);
	$('select[name$="enrollment[START_DATE]"]').on('change', sendNotificationEnable);
});
