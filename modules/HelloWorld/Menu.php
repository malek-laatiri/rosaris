<?php
$admin = $menu['School_Setup']['admin'];
$new_admin = [];
foreach ($admin as $key => $val) {
    $new_admin[$key] = $val;
    if ($key == 'School_Setup/Schools.php') {
        $new_admin['HelloWorld/HelloWorld.php'] = 'Hello World';
    }
}
$menu['School_Setup']['admin'] = $new_admin;

// Repeat for teacher
$teacher = $menu['School_Setup']['teacher'];
$new_teacher = [];
foreach ($teacher as $key => $val) {
    $new_teacher[$key] = $val;
    if ($key == 'School_Setup/Schools.php') {
        $new_teacher['HelloWorld/HelloWorld.php'] = 'Hello World';
    }
}
$menu['School_Setup']['teacher'] = $new_teacher;

// Repeat for parent
$parent = $menu['School_Setup']['parent'];
$new_parent = [];
foreach ($parent as $key => $val) {
    $new_parent[$key] = $val;
    if ($key == 'School_Setup/Schools.php') {
        $new_parent['HelloWorld/HelloWorld.php'] = 'Hello World';
    }
}
$menu['School_Setup']['parent'] = $new_parent;
