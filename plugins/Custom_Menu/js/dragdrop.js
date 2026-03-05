/**
 * JS Drag and drop functions
 *
 * @link https://developer.mozilla.org/en-US/docs/Web/API/HTML_Drag_and_Drop_API
 * @link https://web.dev/articles/drag-and-drop
 *
 * @package Custom Menu plugin
 */

function customMenuOnDragstart(ev) {
	console.log(ev);
	// Add the target element's id to the data transfer object
	ev.dataTransfer.setData("application/rosariosis-custom-menu-id", ev.target.id);
	// Add the target element's Y position to the data transfer object
	ev.dataTransfer.setData("application/rosariosis-custom-menu-y", ev.layerY);

	ev.dataTransfer.effectAllowed = "move";
	ev.target.style.opacity = '0.4';
}

function customMenuOnDragover(ev) {
	ev.preventDefault();
	ev.dataTransfer.dropEffect = "move";
}

function customMenuOnDrop(ev) {
	console.log(ev);
	ev.preventDefault();

	// Get the id of the target
	const dragStartId = ev.dataTransfer.getData("application/rosariosis-custom-menu-id");
	// Get back the start Y position
	const dragStartY = ev.dataTransfer.getData("application/rosariosis-custom-menu-y");
	const dropY = ev.layerY;

	const dragStartEl = document.getElementById(dragStartId);

	const targ = ev.target;

	// Insert before the target DOM
	if ( targ.id === 'dropbox' ) {
		//ev.target.appendChild(document.getElementById(data));
	} else if (dropY > dragStartY) { // Moved down, insert after (before nextSibling)
		if ( targ.localName === 'span' ) {
			targ.parentNode.parentNode.insertBefore(dragStartEl, targ.parentNode.nextSibling);
		} else { // h3
			targ.parentNode.insertBefore(dragStartEl, targ.nextSibling);
		}
	} else { // Moved up, instert before
		if ( targ.localName === 'span' ) {
			targ.parentNode.parentNode.insertBefore(dragStartEl, targ.parentNode);
		} else { // h3
			targ.parentNode.insertBefore(dragStartEl, targ);
		}
	}

	dragStartEl.style.opacity = '1';
}

$('#dropbox').on('drop', function() {
	customMenuOnDrop(event);
});

$('#dropbox').on('dragover', function() {
	customMenuOnDragover(event);
});

$('.dashboard-module-title').on('dragstart', function() {
	customMenuOnDragstart(event);
});
