/**********************************************************************
 install.sql for HelloWorld module
***********************************************************************/

/*******************************************************
 profile_id:
 	- 0: student
 	- 1: admin
 	- 2: teacher
 	- 3: parent
 modname: should match Menu.php entries
 can_use: 'Y'
 can_edit: 'Y' or null
*************************************************/

-- Admin permission
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit)
SELECT 1, 'HelloWorld/HelloWorld.php', 'Y', 'Y'
WHERE NOT EXISTS (SELECT profile_id
    FROM profile_exceptions
    WHERE modname='HelloWorld/HelloWorld.php'
      AND profile_id=1);

-- Teacher permission
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit)
SELECT 2, 'HelloWorld/HelloWorld.php', 'Y', NULL
WHERE NOT EXISTS (SELECT profile_id
    FROM profile_exceptions
    WHERE modname='HelloWorld/HelloWorld.php'
      AND profile_id=2);

-- Parent permission
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit)
SELECT 3, 'HelloWorld/HelloWorld.php', 'Y', NULL
WHERE NOT EXISTS (SELECT profile_id
    FROM profile_exceptions
    WHERE modname='HelloWorld/HelloWorld.php'
      AND profile_id=3);
