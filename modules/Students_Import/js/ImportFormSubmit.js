/**
 * Import Form Submit JS
 *
 * @package Student Import module
 */

$('.import-form').on('submit', importFormSubmit);

var importFormSubmit = function(e){

	e.preventDefault();
	e.stopImmediatePropagation();

	var alertTxt = $('#import_alert_txt').val();

	// Alert.
	if ( ! window.confirm( alertTxt ) ) return false;

	var $buttons = $('.import-button'),
		buttonTxt = $buttons.val(),
		seconds = 5,
		stopButtonHTML = $('#import_stop_button_html').val();

	$buttons.css('pointer-events', 'none').attr('disabled', true).val( buttonTxt + ' ... ' + seconds );

	var countdown = setInterval( function(){
		if ( seconds == 0 ) {
			clearInterval( countdown );
			$('.import-form').off('submit').submit();
			return;
		}

		$buttons.val( buttonTxt + ' ... ' + --seconds );
	}, 1000 );

	// Insert stop button.
	$( stopButtonHTML ).on('click', function(){
		clearInterval( countdown );
		$('.stop-button').remove();
		$buttons.css('pointer-events', '').attr('disabled', false).val( buttonTxt );
		return false;
	}).insertAfter( $buttons );
};
