-- phpMyAdmin SQL Dump
-- version 4.9.5deb2
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Mar 03, 2026 at 09:24 PM
-- Server version: 8.0.42-0ubuntu0.20.04.1
-- PHP Version: 8.2.24

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `rosariosis_db`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`rosariosis_user`@`localhost` PROCEDURE `calc_cum_cr_gpa` (`mp_id` INTEGER, `s_id` INTEGER)  BEGIN
    UPDATE student_mp_stats
    SET cum_cr_weighted_factor = (case when cr_credits = '0' THEN '0' ELSE cr_weighted_factors/cr_credits END),
        cum_cr_unweighted_factor = (case when cr_credits = '0' THEN '0' ELSE cr_unweighted_factors/cr_credits END)
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
END$$

CREATE DEFINER=`rosariosis_user`@`localhost` PROCEDURE `calc_cum_gpa` (`mp_id` INTEGER, `s_id` INTEGER)  BEGIN
    UPDATE student_mp_stats
    SET cum_weighted_factor = (case when gp_credits = '0' THEN '0' ELSE sum_weighted_factors/gp_credits END),
        cum_unweighted_factor = (case when gp_credits = '0' THEN '0' ELSE sum_unweighted_factors/gp_credits END)
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
END$$

CREATE DEFINER=`rosariosis_user`@`localhost` PROCEDURE `calc_gpa_mp` (`s_id` INTEGER, `mp_id` INTEGER)  BEGIN
    DECLARE oldrec integer;

    SELECT count(*) INTO oldrec FROM student_mp_stats WHERE student_id = s_id and marking_period_id = mp_id;

    IF oldrec > 0 THEN
    UPDATE student_mp_stats sms
    JOIN (
        select
        student_id,
        marking_period_id,
        sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
        sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
        sum(credit_attempted) as gp_credits,
        sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
        sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
        sum( case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
        from student_report_card_grades
        where student_id = s_id
        and marking_period_id = mp_id
        and not gp_scale = 0
        and weighted_gp is not null
        group by student_id, marking_period_id
    ) as rcg
    ON rcg.student_id = sms.student_id and rcg.marking_period_id = sms.marking_period_id
    SET
        sms.sum_weighted_factors = rcg.sum_weighted_factors,
        sms.sum_unweighted_factors = rcg.sum_unweighted_factors,
        sms.cr_weighted_factors = rcg.cr_weighted,
        sms.cr_unweighted_factors = rcg.cr_unweighted,
        sms.gp_credits = rcg.gp_credits,
        sms.cr_credits = rcg.cr_credits;

    ELSE
    INSERT INTO student_mp_stats (student_id, marking_period_id, sum_weighted_factors, sum_unweighted_factors, grade_level_short, cr_weighted_factors, cr_unweighted_factors, gp_credits, cr_credits)
        select
            srcg.student_id,
            srcg.marking_period_id,
            sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
            sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
            (select eg.short_name
                from enroll_grade eg, marking_periods mp
                where eg.student_id = s_id
                and eg.syear = mp.syear
                and eg.school_id = mp.school_id
                and eg.start_date <= mp.end_date
                and mp.marking_period_id = mp_id
                order by eg.start_date desc
                limit 1) as short_name,
            sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
            sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
            sum(credit_attempted) as gp_credits,
            sum(case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
        from student_report_card_grades srcg
        where srcg.student_id = s_id
        and srcg.marking_period_id = mp_id
        and not srcg.gp_scale = 0
        and weighted_gp is not null
        group by srcg.student_id, srcg.marking_period_id, short_name;
    END IF;
END$$

CREATE DEFINER=`rosariosis_user`@`localhost` PROCEDURE `t_update_mp_stats` (`s_id` INTEGER, `mp_id` INTEGER)  BEGIN
    CALL calc_gpa_mp(s_id, mp_id);
    CALL calc_cum_gpa(mp_id, s_id);
    CALL calc_cum_cr_gpa(mp_id, s_id);
END$$

--
-- Functions
--
CREATE DEFINER=`rosariosis_user`@`localhost` FUNCTION `credit` (`cp_id` INTEGER, `mp_id` INTEGER) RETURNS DECIMAL(6,2) BEGIN
    DECLARE course_detail_mp_id integer;
    DECLARE course_detail_mp varchar(3);
    DECLARE course_detail_credits numeric(6,2);
    DECLARE mp_detail_mp_id integer;
    DECLARE mp_detail_mp_type varchar(20);
    DECLARE val_mp_count integer;

    select marking_period_id,mp,credits into course_detail_mp_id,course_detail_mp,course_detail_credits from course_periods where course_period_id = cp_id;
    select marking_period_id,mp_type into mp_detail_mp_id,mp_detail_mp_type from marking_periods where marking_period_id = mp_id;

    IF course_detail_mp_id = mp_detail_mp_id THEN
        RETURN course_detail_credits;
    ELSEIF course_detail_mp = 'FY' AND mp_detail_mp_type = 'semester' THEN
        select count(*) into val_mp_count from marking_periods where parent_id = course_detail_mp_id group by parent_id;
    ELSEIF course_detail_mp = 'FY' and mp_detail_mp_type = 'quarter' THEN
        select count(*) into val_mp_count from marking_periods where grandparent_id = course_detail_mp_id group by grandparent_id;
    ELSEIF course_detail_mp = 'SEM' and mp_detail_mp_type = 'quarter' THEN
        select count(*) into val_mp_count from marking_periods where parent_id = course_detail_mp_id group by parent_id;
    ELSE
        RETURN course_detail_credits;
    END IF;

    IF val_mp_count > 0 THEN
        RETURN course_detail_credits/val_mp_count;
    ELSE
        RETURN course_detail_credits;
    END IF;
END$$

CREATE DEFINER=`rosariosis_user`@`localhost` FUNCTION `set_class_rank_mp` (`mp_id` INTEGER) RETURNS INT BEGIN
    update student_mp_stats sms
    JOIN (
        select mp.marking_period_id, sgm.student_id,
        (select count(*)+1
            from student_mp_stats sgm3
            where sgm3.cum_cr_weighted_factor > sgm.cum_cr_weighted_factor
            and sgm3.marking_period_id = mp.marking_period_id
            and sgm3.student_id in (select distinct sgm2.student_id
                from student_mp_stats sgm2, student_enrollment se2
                where sgm2.student_id = se2.student_id
                and sgm2.marking_period_id = mp.marking_period_id
                and se2.grade_id = se.grade_id
                and se2.syear = se.syear)) as class_rank,
        (select count(*)
            from student_mp_stats sgm4
            where sgm4.marking_period_id = mp.marking_period_id
            and sgm4.student_id in (select distinct sgm5.student_id
                from student_mp_stats sgm5, student_enrollment se3
                where sgm5.student_id = se3.student_id
                and sgm5.marking_period_id = mp.marking_period_id
                and se3.grade_id = se.grade_id
                and se3.syear = se.syear)) as class_size
        from student_enrollment se, student_mp_stats sgm, marking_periods mp
        where se.student_id = sgm.student_id
        and sgm.marking_period_id = mp.marking_period_id
        and mp.marking_period_id = mp_id
        and se.syear = mp.syear
        and not sgm.cum_cr_weighted_factor is null
    ) as class_rank
    ON sms.marking_period_id = class_rank.marking_period_id and sms.student_id = class_rank.student_id
    set sms.cum_rank = class_rank.class_rank, sms.class_size = class_rank.class_size;
    RETURN 1;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `access_log`
--

CREATE TABLE `access_log` (
  `syear` decimal(4,0) NOT NULL,
  `username` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `profile` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `ip_address` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `user_agent` text COLLATE utf8mb4_unicode_520_ci,
  `status` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `access_log`
--

INSERT INTO `access_log` (`syear`, `username`, `profile`, `ip_address`, `user_agent`, `status`, `created_at`, `updated_at`) VALUES
('2025', 'Administrator', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', NULL, '2025-10-05 12:02:04', NULL),
('2025', 'teacher', 'teacher', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 12:02:17', NULL),
('2025', 'student', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 12:10:14', NULL),
('2025', 'parent', 'parent', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 12:10:26', NULL),
('2025', 'administrator', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', NULL, '2025-10-05 12:10:36', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 12:11:23', NULL),
('2025', 'teacher', 'teacher', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 12:12:28', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 12:21:21', NULL),
('2025', 'teacher', 'teacher', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 12:24:02', NULL),
('2025', 'admin', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', NULL, '2025-10-05 13:40:12', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 13:40:29', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 15:13:54', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 16:23:14', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', 'Y', '2025-10-05 22:10:37', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-06 18:39:14', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-06 18:42:34', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-06 18:56:15', NULL),
('2025', 'student', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-06 19:04:23', NULL),
('2025', 'teacher', 'teacher', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-06 19:04:42', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-06 19:04:51', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-06 20:35:32', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-25 14:57:51', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-25 14:58:38', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-10-25 14:58:47', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-12-16 19:11:22', NULL),
('2025', 'teacher', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2025-12-16 19:14:46', NULL),
('2025', 'parent', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2025-12-16 19:15:03', NULL),
('2025', 'teacher', 'teacher', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-12-16 19:15:08', NULL),
('2025', 'student', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-12-16 19:15:26', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2025-12-16 19:15:39', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-22 15:01:58', NULL),
('2025', 'teacher', 'teacher', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-22 15:48:03', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-22 15:48:23', NULL),
('2025', '0f8f87b475', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 21:48:29', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 21:48:33', NULL),
('2025', '50p2fk', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:19:54', NULL),
('2025', '50p2fk', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:20:07', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:20:31', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:22:30', NULL),
('2025', 'gje9ds', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:23:49', NULL),
('2025', 'g0utt0', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:24:14', NULL),
('2025', 'g0utt0', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:24:28', NULL),
('2025', '6oqp05', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:24:42', NULL),
('2025', '57q1k6', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:25:06', NULL),
('2025', 'pf466t', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:25:25', NULL),
('2025', '4woq15', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:29:25', NULL),
('2025', '8p0o1d', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:29:40', NULL),
('2025', 'o94icx', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:34:13', NULL),
('2025', '3xx2xs', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:34:30', NULL),
('2025', 'bq4hy9', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:34:48', NULL),
('2025', 'o94icx', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:35:45', NULL),
('2025', 'a6j9jtxp', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:39:20', NULL),
('2025', '2ourmcs6', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:42:30', NULL),
('2025', 'me69f4d6', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:42:48', NULL),
('2025', '2r17veuf', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-25 22:43:17', NULL),
('2025', 'xs3xmmcb', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:43:33', NULL),
('2025', 'etkvgir6', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 22:44:06', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-25 23:03:09', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 21:01:50', NULL),
('2025', 'EtATr8tTlR', NULL, '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', NULL, '2026-02-28 21:16:26', NULL),
('2025', 'nidr9lz3', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 21:16:47', NULL),
('2025', '4uxek3rp', 'student', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 21:17:08', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 21:17:18', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 21:45:56', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 21:53:45', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 22:07:04', NULL),
('2025', 'teacher', 'teacher', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 22:11:20', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-02-28 22:11:43', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 21:38:32', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 21:42:31', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 21:46:54', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 21:51:01', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 21:56:10', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 21:56:26', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 22:00:38', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 22:06:08', NULL),
('2025', 'admin', 'admin', '127.0.0.1', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36', 'Y', '2026-03-01 22:09:48', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `accounting_categories`
--

CREATE TABLE `accounting_categories` (
  `id` int NOT NULL,
  `school_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `type` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_incomes`
--

CREATE TABLE `accounting_incomes` (
  `assigned_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `category_id` int DEFAULT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_payments`
--

CREATE TABLE `accounting_payments` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `staff_id` int DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int DEFAULT NULL,
  `amount` decimal(14,2) NOT NULL,
  `payment_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_salaries`
--

CREATE TABLE `accounting_salaries` (
  `staff_id` int NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `address`
--

CREATE TABLE `address` (
  `address_id` int NOT NULL,
  `house_no` decimal(5,0) DEFAULT NULL,
  `direction` varchar(2) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `street` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `apt` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `zipcode` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `city` text COLLATE utf8mb4_unicode_520_ci,
  `state` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mail_street` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mail_city` text COLLATE utf8mb4_unicode_520_ci,
  `mail_state` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mail_zipcode` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `address` text COLLATE utf8mb4_unicode_520_ci,
  `mail_address` text COLLATE utf8mb4_unicode_520_ci,
  `phone` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `address`
--

INSERT INTO `address` (`address_id`, `house_no`, `direction`, `street`, `apt`, `zipcode`, `city`, `state`, `mail_street`, `mail_city`, `mail_state`, `mail_zipcode`, `address`, `mail_address`, `phone`, `created_at`, `updated_at`) VALUES
(0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No Address', NULL, NULL, '2025-10-05 12:01:13', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `address_fields`
--

CREATE TABLE `address_fields` (
  `id` int NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `address_field_categories`
--

CREATE TABLE `address_field_categories` (
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `residence` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mailing` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_calendar`
--

CREATE TABLE `attendance_calendar` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `school_date` date NOT NULL,
  `minutes` int DEFAULT NULL,
  `block` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `calendar_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_calendars`
--

CREATE TABLE `attendance_calendars` (
  `school_id` int NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `calendar_id` int NOT NULL,
  `default_calendar` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `attendance_calendars`
--

INSERT INTO `attendance_calendars` (`school_id`, `title`, `syear`, `calendar_id`, `default_calendar`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, 'Principal', '2025', 1, 'Y', NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29');

-- --------------------------------------------------------

--
-- Table structure for table `attendance_codes`
--

CREATE TABLE `attendance_codes` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `state_code` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_code` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `table_name` int DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `attendance_codes`
--

INSERT INTO `attendance_codes` (`id`, `syear`, `school_id`, `title`, `short_name`, `type`, `state_code`, `default_code`, `table_name`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, '2025', 1, 'Absent', 'A', 'teacher', 'A', NULL, 0, NULL, '2025-10-05 12:01:13', NULL),
(2, '2025', 1, 'Présent', 'P', 'teacher', 'P', 'Y', 0, NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:30'),
(3, '2025', 1, 'Retard', 'R', 'teacher', 'P', NULL, 0, NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:30'),
(4, '2025', 1, 'Absence justifiée', 'AJ', 'official', 'A', NULL, 0, NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `attendance_code_categories`
--

CREATE TABLE `attendance_code_categories` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_completed`
--

CREATE TABLE `attendance_completed` (
  `staff_id` int NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int NOT NULL,
  `table_name` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_day`
--

CREATE TABLE `attendance_day` (
  `student_id` int NOT NULL,
  `school_date` date NOT NULL,
  `minutes_present` int DEFAULT NULL,
  `state_value` decimal(2,1) DEFAULT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `marking_period_id` int DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_period`
--

CREATE TABLE `attendance_period` (
  `student_id` int NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int NOT NULL,
  `attendance_code` int DEFAULT NULL,
  `attendance_teacher_code` int DEFAULT NULL,
  `attendance_reason` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `admin` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_period_id` int DEFAULT NULL,
  `marking_period_id` int DEFAULT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `billing_fees`
--

CREATE TABLE `billing_fees` (
  `student_id` int NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `waived_fee_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  `created_by` text COLLATE utf8mb4_unicode_520_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `billing_payments`
--

CREATE TABLE `billing_payments` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `student_id` int NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `payment_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `refunded_payment_id` int DEFAULT NULL,
  `lunch_payment` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  `created_by` text COLLATE utf8mb4_unicode_520_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `calendar_events`
--

CREATE TABLE `calendar_events` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `school_date` date DEFAULT NULL,
  `title` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `config`
--

CREATE TABLE `config` (
  `school_id` int NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `config_value` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `config`
--

INSERT INTO `config` (`school_id`, `title`, `config_value`, `created_at`, `updated_at`) VALUES
(0, 'LOGIN', 'Yes', '2025-10-05 12:01:13', '2025-10-05 12:21:55'),
(0, 'VERSION', '12.7.3', '2025-10-05 12:01:13', '2026-03-01 22:00:36'),
(0, 'TITLE', 'الفرقان لتعليم القرآن بمساكن', '2025-10-05 12:01:13', '2025-10-05 13:43:11'),
(0, 'NAME', 'الفرقان لتعليم القرآ', '2025-10-05 12:01:13', '2025-10-05 13:43:11'),
(0, 'MODULES', 'a:19:{s:12:\"School_Setup\";b:1;s:8:\"Students\";b:1;s:5:\"Users\";b:1;s:10:\"Scheduling\";b:0;s:6:\"Grades\";b:0;s:10:\"Attendance\";b:0;s:11:\"Eligibility\";b:0;s:10:\"Discipline\";b:0;s:10:\"Accounting\";b:0;s:15:\"Student_Billing\";b:0;s:12:\"Food_Service\";b:0;s:9:\"Resources\";b:0;s:6:\"Custom\";b:1;s:15:\"Student_ID_Card\";b:1;s:15:\"Students_Import\";b:1;s:11:\"hello_world\";b:0;s:7:\"Example\";b:0;s:5:\"Email\";b:0;s:10:\"HelloWorld\";b:1;}', '2025-10-05 12:01:13', '2026-02-28 23:25:06'),
(0, 'PLUGINS', 'a:3:{s:6:\"Moodle\";b:0;s:8:\"REST_API\";b:1;s:23:\"Content_Security_Policy\";b:1;}', '2025-10-05 12:01:13', '2026-03-01 22:00:36'),
(0, 'THEME', 'FlatSIS', '2025-10-05 12:01:13', '2026-03-01 21:48:04'),
(0, 'THEME_FORCE', NULL, '2025-10-05 12:01:13', '2026-03-01 21:47:29'),
(0, 'CREATE_USER_ACCOUNT', 'Y', '2025-10-05 12:01:13', '2026-03-01 21:48:30'),
(0, 'CREATE_STUDENT_ACCOUNT', NULL, '2025-10-05 12:01:13', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_AUTOMATIC_ACTIVATION', NULL, '2025-10-05 12:01:13', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_DEFAULT_SCHOOL', '1', '2025-10-05 12:01:13', '2026-03-01 21:48:30'),
(0, 'STUDENTS_EMAIL_FIELD', NULL, '2025-10-05 12:01:14', NULL),
(0, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2025-10-05 12:01:14', NULL),
(1, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2025-10-05 12:01:14', NULL),
(0, 'LIMIT_EXISTING_CONTACTS_ADDRESSES', NULL, '2025-10-05 12:01:14', NULL),
(0, 'FAILED_LOGIN_LIMIT', '30', '2025-10-05 12:01:14', NULL),
(0, 'PASSWORD_STRENGTH', '2', '2025-10-05 12:01:14', NULL),
(0, 'FORCE_PASSWORD_CHANGE_ON_FIRST_LOGIN', NULL, '2025-10-05 12:01:14', NULL),
(0, 'GRADEBOOK_CONFIG_ADMIN_OVERRIDE', NULL, '2025-10-05 12:01:14', NULL),
(0, 'REMOVE_ACCESS_USERNAME_PREFIX_ADD', NULL, '2025-10-05 12:01:14', NULL),
(1, 'SCHOOL_SYEAR_OVER_2_YEARS', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'ATTENDANCE_FULL_DAY_MINUTES', '0', '2025-10-05 12:01:14', NULL),
(1, 'STUDENTS_USE_MAILING', NULL, '2025-10-05 12:01:14', NULL),
(1, 'CURRENCY', '€', '2025-10-05 12:01:14', '2025-10-05 12:01:29'),
(1, 'DECIMAL_SEPARATOR', ',', '2025-10-05 12:01:14', '2025-10-05 12:01:29'),
(1, 'THOUSANDS_SEPARATOR', '&nbsp;', '2025-10-05 12:01:14', '2025-10-05 12:01:29'),
(1, 'CLASS_RANK_CALCULATE_MPS', NULL, '2025-10-05 12:01:14', NULL),
(0, 'REGISTRATION_FORM', 'a:4:{s:6:\"parent\";a:2:{i:0;a:7:{s:8:\"relation\";s:6:\"Parent\";s:7:\"custody\";s:1:\"Y\";s:9:\"emergency\";s:1:\"Y\";s:7:\"address\";s:1:\"1\";s:4:\"info\";s:0:\"\";s:13:\"info_required\";s:0:\"\";s:6:\"fields\";s:0:\"\";}i:1;a:7:{s:8:\"relation\";s:6:\"Parent\";s:7:\"custody\";s:1:\"Y\";s:9:\"emergency\";s:0:\"\";s:7:\"address\";s:0:\"\";s:4:\"info\";s:0:\"\";s:13:\"info_required\";s:0:\"\";s:6:\"fields\";s:0:\"\";}}s:7:\"address\";a:1:{s:6:\"fields\";s:0:\"\";}s:7:\"contact\";a:0:{}s:7:\"student\";a:1:{s:6:\"fields\";s:8:\"||1||2||\";}}', '2025-10-06 18:39:46', NULL),
(1, 'COURSE_WIDGET_METHOD', NULL, '2025-10-06 19:05:07', NULL),
(0, 'CONTENT_SECURITY_POLICY', 'script-src \'self\' \'unsafe-eval\' \'report-sample\'; style-src \'self\' \'unsafe-inline\'; connect-src \'self\'; form-action \'self\'; base-uri \'self\'; frame-ancestors \'none\'; object-src \'none\'; report-uri plugins/Content_Security_Policy/SaveReport.php', '2026-03-01 22:00:36', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_DEFAULT_SCHOOL_FORCE', NULL, '2026-03-01 22:00:36', NULL),
(0, 'CONTENT_SECURITY_POLICY_CRON_DAY', '2026-03-01', '2026-03-01 22:00:36', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `courses`
--

CREATE TABLE `courses` (
  `syear` decimal(4,0) NOT NULL,
  `course_id` int NOT NULL,
  `subject_id` int NOT NULL,
  `school_id` int NOT NULL,
  `grade_level` int DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Title can be multilingual, use ParseMLField()',
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `credit_hours` decimal(6,2) DEFAULT NULL,
  `description` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `course_details`
-- (See below for the actual view)
--
CREATE TABLE `course_details` (
`school_id` int
,`syear` decimal(4,0)
,`marking_period_id` int
,`subject_id` int
,`course_id` int
,`course_period_id` int
,`teacher_id` int
,`course_title` text
,`cp_title` text
,`grade_scale_id` int
,`mp` varchar(3)
,`credits` decimal(6,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `course_periods`
--

CREATE TABLE `course_periods` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `course_period_id` int NOT NULL,
  `course_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `mp` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `marking_period_id` int NOT NULL,
  `teacher_id` int NOT NULL,
  `secondary_teacher_id` int DEFAULT NULL,
  `room` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `total_seats` decimal(10,0) DEFAULT NULL,
  `filled_seats` decimal(10,0) DEFAULT NULL,
  `does_attendance` text COLLATE utf8mb4_unicode_520_ci,
  `does_honor_roll` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `does_class_rank` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `gender_restriction` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `house_restriction` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `availability` decimal(10,0) DEFAULT NULL,
  `parent_id` int DEFAULT NULL,
  `calendar_id` int DEFAULT NULL,
  `does_breakoff` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `grade_scale_id` int DEFAULT NULL,
  `credits` decimal(6,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `course_period_school_periods`
--

CREATE TABLE `course_period_school_periods` (
  `course_period_school_periods_id` int NOT NULL,
  `course_period_id` int NOT NULL,
  `period_id` int NOT NULL,
  `days` varchar(7) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `course_subjects`
--

CREATE TABLE `course_subjects` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `subject_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Title can be multilingual, use ParseMLField()',
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `csp_reports`
--

CREATE TABLE `csp_reports` (
  `id` int NOT NULL,
  `full_report` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `violated_directive` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `blocked_uri` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `script_sample` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `csp_reports`
--

INSERT INTO `csp_reports` (`id`, `full_report`, `violated_directive`, `blocked_uri`, `script_sample`, `created_at`) VALUES
(1, '{\"document-uri\":\"http:\\/\\/localhost:8000\\/Modules.php?modname=School_Setup\\/Calendar.php\",\"referrer\":\"http:\\/\\/localhost:8000\\/index.php?locale=ar_TN.utf8\",\"violated-directive\":\"style-src-elem\",\"effective-directive\":\"style-src-elem\",\"original-policy\":\"script-src \'self\' \'unsafe-eval\' \'report-sample\'; style-src \'self\' \'unsafe-inline\'; connect-src \'self\'; form-action \'self\'; base-uri \'self\'; frame-ancestors \'none\'; object-src \'none\'; report-uri plugins\\/Content_Security_Policy\\/SaveReport.php\",\"disposition\":\"report\",\"blocked-uri\":\"https:\\/\\/fonts.googleapis.com\\/css2?family=Cairo:wght@300;400;600;700&display=swap\",\"line-number\":1,\"column-number\":118925,\"source-file\":\"http:\\/\\/localhost:8000\\/assets\\/js\\/plugins.min.js\",\"status-code\":200,\"script-sample\":\"\"}', 'style-src', 'https://fonts.googleapis.com/css2?family=Cairo:wght@300;400;600;700&display=swap', NULL, '2026-03-01 22:07:01'),
(2, '{\"document-uri\":\"http:\\/\\/localhost:8000\\/Modules.php?modname=misc\\/Portal.php\",\"referrer\":\"\",\"violated-directive\":\"style-src-elem\",\"effective-directive\":\"style-src-elem\",\"original-policy\":\"script-src \'self\' \'unsafe-eval\' \'report-sample\'; style-src \'self\' \'unsafe-inline\'; connect-src \'self\'; form-action \'self\'; base-uri \'self\'; frame-ancestors \'none\'; object-src \'none\'; report-uri plugins\\/Content_Security_Policy\\/SaveReport.php\",\"disposition\":\"report\",\"blocked-uri\":\"https:\\/\\/fonts.googleapis.com\\/css2?family=Cairo:wght@300;400;600;700&display=swap\",\"line-number\":1,\"column-number\":118925,\"source-file\":\"http:\\/\\/localhost:8000\\/assets\\/js\\/plugins.min.js\",\"status-code\":200,\"script-sample\":\"\"}', 'style-src', 'https://fonts.googleapis.com/css2?family=Cairo:wght@300;400;600;700&display=swap', NULL, '2026-03-01 22:08:49');

-- --------------------------------------------------------

--
-- Table structure for table `custom_fields`
--

CREATE TABLE `custom_fields` (
  `id` int NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `custom_fields`
--

INSERT INTO `custom_fields` (`id`, `type`, `title`, `sort_order`, `select_options`, `category_id`, `required`, `default_selection`, `created_at`, `updated_at`) VALUES
(200000000, 'select', 'Gender|fr_FR.utf8:Sexe', '0', 'ذكر\r\nأنثى', 1, NULL, NULL, '2025-10-05 12:01:14', '2026-02-22 15:54:36'),
(200000003, 'text', 'Identification Number|fr_FR.utf8:Numéro d\'identification', '3', NULL, 1, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000004, 'date', 'Birthdate|fr_FR.utf8:Date de naissance', '4', NULL, 1, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000005, 'select', 'Language|fr_FR.utf8:Langue', '5', 'Français\nAnglais', 1, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000006, 'text', 'Physician|fr_FR.utf8:Médecin', '6', NULL, 2, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000007, 'text', 'Physician Phone|fr_FR.utf8:Téléphone médecin', '7', NULL, 2, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000008, 'text', 'Preferred Hospital|fr_FR.utf8:Hôpital préféré', '8', NULL, 2, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000009, 'textarea', 'Comments|fr_FR.utf8:Commentaires', '9', NULL, 2, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000010, 'radio', 'Has Doctor\'s Note|fr_FR.utf8:A un mot du docteur', '10', NULL, 2, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000011, 'textarea', 'Doctor\'s Note Comments|fr_FR.utf8:Commentaires du mot du docteur', '11', NULL, 2, NULL, NULL, '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(200000012, 'select', '|fr_FR.utf8:Montant des frais d’inscription payés|en_US.utf8:Registration fee paid|ar_AE.utf8:مبلغ الترسيم المدفوع', '6', '40 DT\r\n20 DT سداسي أول\r\nمعفى\r\n10 DT\r\n20 DT للعام الكامل', 1, NULL, NULL, '2026-02-22 15:33:03', '2026-02-22 16:24:53'),
(200000013, 'select', '|ar_AE.utf8:رقم الحالة المدنية|en_US.utf8:Civil status number|fr_FR.utf8:Numéro d’état civil', NULL, NULL, 6, NULL, NULL, '2026-02-22 15:40:05', '2026-02-22 15:40:45'),
(200000014, 'select', '|en_US.utf8:Name and lastname of the parent|ar_AE.utf8:إسم و لقب الولي|fr_FR.utf8:Nom et prénom du parent', NULL, NULL, 6, NULL, NULL, '2026-02-22 15:41:00', NULL),
(200000015, 'select', '|en_US.utf8:Age group|ar_AE.utf8:الفئة العمرية|fr_FR.utf8:Tranche d’âge', '1', '6 - 8\r\n9 - 12\r\n9 - 12/ 13-17 (للحالات الخاصة)\r\n13- 25\r\nفوق 26\r\n', 1, NULL, NULL, '2026-02-22 15:43:35', '2026-02-22 15:56:11'),
(200000016, 'select', '|ar_AE.utf8:رقم الهاتف|en_US.utf8:Phone|fr_FR.utf8:Telephone', '3', NULL, 6, NULL, NULL, '2026-02-25 23:06:09', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_fields`
--

CREATE TABLE `discipline_fields` (
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `data_type` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `column_name` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `discipline_fields`
--

INSERT INTO `discipline_fields` (`id`, `title`, `short_name`, `data_type`, `column_name`, `created_at`, `updated_at`) VALUES
(1, 'Violation', '', 'multiple_checkbox', 'CATEGORY_1', '2025-10-05 12:01:14', NULL),
(2, 'Detention Assigned', '', 'multiple_radio', 'CATEGORY_2', '2025-10-05 12:01:14', NULL),
(3, 'Parents Contacted By Teacher', '', 'checkbox', 'CATEGORY_3', '2025-10-05 12:01:14', NULL),
(4, 'Parent Contacted by Administrator', '', 'text', 'CATEGORY_4', '2025-10-05 12:01:14', NULL),
(5, 'Suspensions (Office Only)', '', 'multiple_checkbox', 'CATEGORY_5', '2025-10-05 12:01:14', NULL),
(6, 'Comments', '', 'textarea', 'CATEGORY_6', '2025-10-05 12:01:14', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_field_usage`
--

CREATE TABLE `discipline_field_usage` (
  `id` int NOT NULL,
  `discipline_field_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `discipline_field_usage`
--

INSERT INTO `discipline_field_usage` (`id`, `discipline_field_id`, `syear`, `school_id`, `title`, `select_options`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 3, '2025', 1, 'Parents contactés par l\'enseignant', '', '4', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(2, 4, '2025', 1, 'Parents contactés par l\'administrateur', '', '5', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(3, 6, '2025', 1, 'Commentaires', '', '6', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(4, 1, '2025', 1, 'Violation', 'Absent du cours\nInjures, vulgarité, language offensif\nInsubordination (désobéissance, comportement irrespectueux)\nIvre (alcool ou drogues)\nParle sans avoir la parole\nHarcèlement\nSe bat\nAutre', '1', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(5, 2, '2025', 1, 'Sanction', '10 Minutes\n20 Minutes\n30 Minutes\nExclusion envisagée', '2', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(6, 5, '2025', 1, 'Exclusions (secrétariat)', 'Demi-journée\nRetenue à l\'école\n1 Jour\n2 Jours\n3 Jours\n5 Jours\n7 Jours\nExpulsion', '3', '2025-10-05 12:01:14', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `discipline_referrals`
--

CREATE TABLE `discipline_referrals` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `student_id` int NOT NULL,
  `school_id` int NOT NULL,
  `staff_id` int DEFAULT NULL,
  `entry_date` date DEFAULT NULL,
  `referral_date` date DEFAULT NULL,
  `category_1` text COLLATE utf8mb4_unicode_520_ci,
  `category_2` text COLLATE utf8mb4_unicode_520_ci,
  `category_3` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `category_4` text COLLATE utf8mb4_unicode_520_ci,
  `category_5` text COLLATE utf8mb4_unicode_520_ci,
  `category_6` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `eligibility`
--

CREATE TABLE `eligibility` (
  `student_id` int NOT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `school_date` date DEFAULT NULL,
  `period_id` int DEFAULT NULL,
  `eligibility_code` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_period_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `eligibility_activities`
--

CREATE TABLE `eligibility_activities` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `eligibility_activities`
--

INSERT INTO `eligibility_activities` (`id`, `syear`, `school_id`, `title`, `start_date`, `end_date`, `comment`, `created_at`, `updated_at`) VALUES
(1, '2025', 1, 'Boy\'s Basketball', '2025-10-01', '2026-04-12', NULL, '2025-10-05 12:01:14', NULL),
(2, '2025', 1, 'Chess Team', '2025-09-03', '2026-06-05', NULL, '2025-10-05 12:01:14', NULL),
(3, '2025', 1, 'Girl\'s Basketball', '2025-10-01', '2026-04-12', NULL, '2025-10-05 12:01:14', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `eligibility_completed`
--

CREATE TABLE `eligibility_completed` (
  `staff_id` int NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `enroll_grade`
-- (See below for the actual view)
--
CREATE TABLE `enroll_grade` (
`id` int
,`syear` decimal(4,0)
,`school_id` int
,`student_id` int
,`start_date` date
,`end_date` date
,`short_name` varchar(3)
,`title` varchar(50)
);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_accounts`
--

CREATE TABLE `food_service_accounts` (
  `account_id` int NOT NULL,
  `balance` decimal(9,2) NOT NULL,
  `transaction_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_categories`
--

CREATE TABLE `food_service_categories` (
  `category_id` int NOT NULL,
  `school_id` int NOT NULL,
  `menu_id` int NOT NULL,
  `title` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_categories`
--

INSERT INTO `food_service_categories` (`category_id`, `school_id`, `menu_id`, `title`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 'Éléments du repas', '1', '2025-10-05 12:01:14', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `food_service_items`
--

CREATE TABLE `food_service_items` (
  `item_id` int NOT NULL,
  `school_id` int NOT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `description` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `icon` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `price` decimal(9,2) NOT NULL,
  `price_reduced` decimal(9,2) DEFAULT NULL,
  `price_free` decimal(9,2) DEFAULT NULL,
  `price_staff` decimal(9,2) NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_items`
--

INSERT INTO `food_service_items` (`item_id`, `school_id`, `short_name`, `sort_order`, `description`, `icon`, `price`, `price_reduced`, `price_free`, `price_staff`, `created_at`, `updated_at`) VALUES
(1, 1, 'HOTL', '1', 'Repas élève', 'Lunch.png', '1.65', '0.40', '0.00', '2.35', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(2, 1, 'MILK', '2', 'Lait', 'Milk.png', '0.25', NULL, NULL, '0.50', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(3, 1, 'XTRA', '3', 'Sandwich', 'Sandwich.png', '0.50', NULL, NULL, '1.00', '2025-10-05 12:01:14', '2025-10-05 12:01:30'),
(4, 1, 'PIZZA', '4', 'Pizza extra', 'Pizza.png', '1.00', NULL, NULL, '1.00', '2025-10-05 12:01:14', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `food_service_menus`
--

CREATE TABLE `food_service_menus` (
  `menu_id` int NOT NULL,
  `school_id` int NOT NULL,
  `title` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_menus`
--

INSERT INTO `food_service_menus` (`menu_id`, `school_id`, `title`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 'Repas', '1', '2025-10-05 12:01:14', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `food_service_menu_items`
--

CREATE TABLE `food_service_menu_items` (
  `menu_item_id` int NOT NULL,
  `school_id` int NOT NULL,
  `menu_id` int NOT NULL,
  `item_id` int NOT NULL,
  `category_id` int DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `does_count` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_menu_items`
--

INSERT INTO `food_service_menu_items` (`menu_item_id`, `school_id`, `menu_id`, `item_id`, `category_id`, `sort_order`, `does_count`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 1, 1, NULL, NULL, '2025-10-05 12:01:14', NULL),
(2, 1, 1, 2, 1, NULL, NULL, '2025-10-05 12:01:14', NULL),
(3, 1, 1, 3, 1, NULL, NULL, '2025-10-05 12:01:14', NULL),
(4, 1, 1, 4, 1, NULL, NULL, '2025-10-05 12:01:14', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_accounts`
--

CREATE TABLE `food_service_staff_accounts` (
  `staff_id` int NOT NULL,
  `status` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `barcode` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `balance` decimal(9,2) NOT NULL,
  `transaction_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_transactions`
--

CREATE TABLE `food_service_staff_transactions` (
  `transaction_id` int NOT NULL,
  `staff_id` int NOT NULL,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `balance` decimal(9,2) DEFAULT NULL,
  `timestamp` datetime DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `seller_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_transaction_items`
--

CREATE TABLE `food_service_staff_transaction_items` (
  `item_id` int NOT NULL,
  `transaction_id` int NOT NULL,
  `menu_item_id` int DEFAULT NULL COMMENT 'References food_service_menu_items(menu_item_id)',
  `amount` decimal(9,2) DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_student_accounts`
--

CREATE TABLE `food_service_student_accounts` (
  `student_id` int NOT NULL,
  `account_id` int NOT NULL,
  `discount` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `status` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `barcode` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_transactions`
--

CREATE TABLE `food_service_transactions` (
  `transaction_id` int NOT NULL,
  `account_id` int NOT NULL,
  `student_id` int DEFAULT NULL,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `discount` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `balance` decimal(9,2) DEFAULT NULL,
  `timestamp` datetime DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `seller_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_transaction_items`
--

CREATE TABLE `food_service_transaction_items` (
  `item_id` int NOT NULL,
  `transaction_id` int NOT NULL,
  `menu_item_id` int DEFAULT NULL COMMENT 'References food_service_menu_items(menu_item_id)',
  `amount` decimal(9,2) DEFAULT NULL,
  `discount` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_assignments`
--

CREATE TABLE `gradebook_assignments` (
  `assignment_id` int NOT NULL,
  `staff_id` int NOT NULL,
  `marking_period_id` int NOT NULL,
  `course_period_id` int DEFAULT NULL,
  `course_id` int DEFAULT NULL,
  `assignment_type_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `points` int NOT NULL,
  `description` longtext COLLATE utf8mb4_unicode_520_ci,
  `file` text COLLATE utf8mb4_unicode_520_ci,
  `default_points` int DEFAULT NULL,
  `submission` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `weight` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_assignment_types`
--

CREATE TABLE `gradebook_assignment_types` (
  `assignment_type_id` int NOT NULL,
  `staff_id` int NOT NULL,
  `course_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `final_grade_percent` decimal(6,5) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `color` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_mp` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_grades`
--

CREATE TABLE `gradebook_grades` (
  `student_id` int NOT NULL,
  `course_period_id` int NOT NULL,
  `assignment_id` int NOT NULL,
  `points` decimal(6,2) DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `grades_completed`
--

CREATE TABLE `grades_completed` (
  `staff_id` int NOT NULL,
  `marking_period_id` int NOT NULL,
  `course_period_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `history_marking_periods`
--

CREATE TABLE `history_marking_periods` (
  `parent_id` int DEFAULT NULL,
  `mp_type` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `post_end_date` date DEFAULT NULL,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `marking_period_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `lunch_period`
--

CREATE TABLE `lunch_period` (
  `student_id` int NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int NOT NULL,
  `attendance_code` int DEFAULT NULL,
  `attendance_teacher_code` int DEFAULT NULL,
  `attendance_reason` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `admin` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_period_id` int DEFAULT NULL,
  `marking_period_id` int DEFAULT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `table_name` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `marking_periods`
-- (See below for the actual view)
--
CREATE TABLE `marking_periods` (
`marking_period_id` int
,`mp_source` varchar(7)
,`syear` decimal(4,0)
,`school_id` int
,`mp_type` varchar(20)
,`title` varchar(50)
,`short_name` varchar(10)
,`sort_order` decimal(10,0)
,`parent_id` bigint
,`grandparent_id` bigint
,`start_date` date
,`end_date` date
,`post_start_date` date
,`post_end_date` date
,`does_grades` varchar(1)
,`does_comments` varchar(1)
);

-- --------------------------------------------------------

--
-- Table structure for table `moodlexrosario`
--

CREATE TABLE `moodlexrosario` (
  `column` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `rosario_id` int NOT NULL,
  `moodle_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `moodlexrosario`
--

INSERT INTO `moodlexrosario` (`column`, `rosario_id`, `moodle_id`, `created_at`, `updated_at`) VALUES
('staff_id', 1, 2, '2025-10-05 12:01:14', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `people`
--

CREATE TABLE `people` (
  `person_id` int NOT NULL,
  `last_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `first_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `middle_name` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_fields`
--

CREATE TABLE `people_fields` (
  `id` int NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_field_categories`
--

CREATE TABLE `people_field_categories` (
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `custody` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `emergency` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_join_contacts`
--

CREATE TABLE `people_join_contacts` (
  `id` int NOT NULL,
  `person_id` int DEFAULT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `value` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_notes`
--

CREATE TABLE `portal_notes` (
  `id` int NOT NULL,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `content` longtext COLLATE utf8mb4_unicode_520_ci,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `published_user` int DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `published_profiles` text COLLATE utf8mb4_unicode_520_ci,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_polls`
--

CREATE TABLE `portal_polls` (
  `id` int NOT NULL,
  `school_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `votes_number` int DEFAULT NULL,
  `display_votes` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `published_user` int DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `published_profiles` text COLLATE utf8mb4_unicode_520_ci,
  `students_teacher_id` int DEFAULT NULL,
  `excluded_users` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_poll_questions`
--

CREATE TABLE `portal_poll_questions` (
  `id` int NOT NULL,
  `portal_poll_id` int NOT NULL,
  `question` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `type` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `options` text COLLATE utf8mb4_unicode_520_ci,
  `votes` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `profile_exceptions`
--

CREATE TABLE `profile_exceptions` (
  `profile_id` int NOT NULL,
  `modname` varchar(150) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `can_use` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `can_edit` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `profile_exceptions`
--

INSERT INTO `profile_exceptions` (`profile_id`, `modname`, `can_use`, `can_edit`, `created_at`, `updated_at`) VALUES
(0, 'Attendance/DailySummary.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Attendance/StudentSummary.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Custom/Registration.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Eligibility/Student.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Eligibility/StudentList.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Food_Service/Accounts.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Food_Service/DailyMenus.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Food_Service/MenuItems.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Food_Service/Statements.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Grades/FinalGrades.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Grades/GPARankList.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Grades/ProgressReports.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Grades/ReportCards.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Grades/StudentAssignments.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Grades/StudentGrades.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Grades/Transcripts.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Resources/Resources.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Scheduling/Courses.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Scheduling/Requests.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Scheduling/Schedule.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'School_Setup/Calendar.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'School_Setup/Schools.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Student_Billing/DailyTransactions.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Student_Billing/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Student_Billing/StudentFees.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Student_Billing/StudentPayments.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Students/Student.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Students/Student.php&category_id=1', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Students/Student.php&category_id=3', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(0, 'Users/Preferences.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(1, 'Accounting/Categories.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/DailyTransactions.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/Expenses.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/Expenses.php&modfunc=remove', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/Incomes.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/Incomes.php&modfunc=remove', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/Salaries.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/Salaries.php&modfunc=remove', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/StaffBalances.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/StaffPayments.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/StaffPayments.php&modfunc=remove', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Accounting/Statements.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/AddAbsences.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/Administration.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/AttendanceCodes.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/DailySummary.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/DuplicateAttendance.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/FixDailyAttendance.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/Percent.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Attendance/TeacherCompletion.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Custom/AttendanceSummary.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Custom/CreateParents.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Custom/MyReport.php', NULL, NULL, '2025-10-05 12:01:16', NULL),
(1, 'Custom/NotifyParents.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Custom/Registration.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Custom/RemoveAccess.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/CategoryBreakdown.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/CategoryBreakdownTime.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/DisciplineForm.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/MakeReferral.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/ReferralForm.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/ReferralLog.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/Referrals.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Discipline/StudentFieldBreakdown.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Eligibility/Activities.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Eligibility/AddActivity.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Eligibility/EntryTimes.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Eligibility/Student.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Eligibility/StudentList.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Eligibility/TeacherCompletion.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Email/EmailStudents.php', 'Y', 'Y', '2026-02-28 22:14:15', NULL),
(1, 'Email/EmailUsers.php', 'Y', 'Y', '2026-02-28 22:14:15', NULL),
(1, 'Food_Service/Accounts.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/ActivityReport.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/DailyMenus.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/Kiosk.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/MenuItems.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/MenuReports.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/Menus.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/Reminders.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/ServeMenus.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/Statements.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/Transactions.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Food_Service/TransactionsReport.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/Configuration.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/EditHistoryMarkingPeriods.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/EditReportCardGrades.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/FinalGrades.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/FixGPA.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/GPARankList.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/GradeBreakdown.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/HonorRoll.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/MassCreateAssignments.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/ProgressReports.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/ReportCardCommentCodes.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/ReportCardComments.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/ReportCardGrades.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/ReportCards.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/StudentGrades.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/TeacherCompletion.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Grades/Transcripts.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'HelloWorld/HelloWorld.php', 'Y', 'Y', '2026-02-28 23:25:54', NULL),
(1, 'Resources/Resources.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Scheduling/AddDrop.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/Courses.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/IncompleteSchedules.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/MassDrops.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/MassRequests.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/MassSchedule.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/PrintClassLists.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/PrintClassPictures.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/PrintRequests.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/PrintSchedules.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/Requests.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/RequestsReport.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/Schedule.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/Scheduler.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Scheduling/ScheduleReport.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/AccessLog.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'School_Setup/Calendar.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/Configuration.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'School_Setup/CopySchool.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/DatabaseBackup.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'School_Setup/GradeLevels.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/MarkingPeriods.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/Periods.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/PortalNotes.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/PortalPolls.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'School_Setup/Rollover.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/SchoolFields.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'School_Setup/Schools.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Student_Billing/DailyTransactions.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/Fees.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/MassAssignFees.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/MassAssignPayments.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/Statements.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/StudentBalances.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/StudentFees.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/StudentPayments.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_Billing/StudentPayments.php&modfunc=remove', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Student_ID_Card/StudentIDCard.php', 'Y', 'Y', '2025-10-05 13:48:39', NULL),
(1, 'Students_Import/StudentsImport.php', 'Y', 'Y', '2025-10-06 20:35:46', NULL),
(1, 'Students/AddDrop.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/AddUsers.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/AdvancedReport.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/AssignOtherInfo.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/EnrollmentCodes.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/Letters.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/PrintStudentInfo.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/Student.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/Student.php&category_id=1', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/Student.php&category_id=2', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/Student.php&category_id=3', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/Student.php&category_id=6', 'Y', 'Y', '2026-02-22 15:31:35', NULL),
(1, 'Students/Student.php&include=General_Info&student_id=new', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/StudentBreakdown.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(1, 'Students/StudentFields.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Students/StudentLabels.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/AddStudents.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/Exceptions.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/Preferences.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/Profiles.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/TeacherPrograms.php&include=Attendance/TakeAttendance.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Users/TeacherPrograms.php&include=Eligibility/EnterEligibility.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/AnomalousGrades.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/Grades.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/InputFinalGrades.php', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(1, 'Users/User.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/User.php&category_id=1', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/User.php&category_id=1&schools', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/User.php&category_id=1&user_profile', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/User.php&category_id=2', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/User.php&category_id=3', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/User.php&staff_id=new', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(1, 'Users/UserFields.php', 'Y', 'Y', '2025-10-05 12:01:14', NULL),
(2, 'Accounting/Salaries.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Accounting/StaffPayments.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Accounting/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Attendance/DailySummary.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Attendance/TakeAttendance.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Discipline/MakeReferral.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(2, 'Discipline/Referrals.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(2, 'Eligibility/EnterEligibility.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Email/EmailStudents.php', 'Y', 'Y', '2026-02-28 22:14:15', NULL),
(2, 'Email/EmailUsers.php', 'Y', 'Y', '2026-02-28 22:14:15', NULL),
(2, 'Food_Service/Accounts.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Food_Service/DailyMenus.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Food_Service/MenuItems.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Food_Service/Statements.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/AnomalousGrades.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/Assignments-new.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/Assignments.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/Configuration.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/FinalGrades.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/GradebookBreakdown.php', 'Y', 'Y', '2025-10-05 12:01:16', NULL),
(2, 'Grades/Grades.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/InputFinalGrades.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/ProgressReports.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/ReportCardCommentCodes.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/ReportCardComments.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/ReportCardGrades.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/ReportCards.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Grades/StudentGrades.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'HelloWorld/HelloWorld.php', 'Y', NULL, '2026-02-28 23:25:54', NULL),
(2, 'Resources/Resources.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Scheduling/Courses.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Scheduling/PrintClassLists.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Scheduling/Schedule.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'School_Setup/Calendar.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'School_Setup/Schools.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Students/AddUsers.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Students/AdvancedReport.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Students/Letters.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Students/Student.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Students/Student.php&category_id=1', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Students/Student.php&category_id=3', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Students/Student.php&category_id=4', 'Y', 'Y', '2025-10-05 12:01:15', NULL),
(2, 'Students/StudentLabels.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Users/Preferences.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Users/User.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Users/User.php&category_id=1', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Users/User.php&category_id=2', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(2, 'Users/User.php&category_id=3', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(3, 'Attendance/DailySummary.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Custom/Registration.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Eligibility/Student.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Eligibility/StudentList.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Food_Service/Accounts.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Food_Service/DailyMenus.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Food_Service/MenuItems.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Food_Service/Statements.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Grades/FinalGrades.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Grades/GPARankList.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Grades/ProgressReports.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Grades/ReportCards.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Grades/StudentAssignments.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Grades/StudentGrades.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Grades/Transcripts.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'HelloWorld/HelloWorld.php', 'Y', NULL, '2026-02-28 23:25:54', NULL),
(3, 'Resources/Resources.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Scheduling/Courses.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Scheduling/Requests.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Scheduling/Schedule.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'School_Setup/Calendar.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(3, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(3, 'School_Setup/Schools.php', 'Y', NULL, '2025-10-05 12:01:15', NULL),
(3, 'Student_Billing/DailyTransactions.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Student_Billing/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Student_Billing/StudentFees.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Student_Billing/StudentPayments.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Students/Student.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Students/Student.php&category_id=1', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Students/Student.php&category_id=3', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Users/Preferences.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Users/User.php', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Users/User.php&category_id=1', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Users/User.php&category_id=2', 'Y', NULL, '2025-10-05 12:01:16', NULL),
(3, 'Users/User.php&category_id=3', 'Y', NULL, '2025-10-05 12:01:16', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `program_config`
--

CREATE TABLE `program_config` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `program` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `program_config`
--

INSERT INTO `program_config` (`syear`, `school_id`, `program`, `title`, `value`, `created_at`, `updated_at`) VALUES
('2025', 1, 'eligibility', 'START_DAY', '1', '2025-10-05 12:01:16', NULL),
('2025', 1, 'eligibility', 'START_HOUR', '23', '2025-10-05 12:01:16', NULL),
('2025', 1, 'eligibility', 'START_MINUTE', '30', '2025-10-05 12:01:16', NULL),
('2025', 1, 'eligibility', 'START_M', 'PM', '2025-10-05 12:01:16', NULL),
('2025', 1, 'eligibility', 'END_DAY', '5', '2025-10-05 12:01:16', NULL),
('2025', 1, 'eligibility', 'END_HOUR', '23', '2025-10-05 12:01:17', NULL),
('2025', 1, 'eligibility', 'END_MINUTE', '30', '2025-10-05 12:01:17', NULL),
('2025', 1, 'eligibility', 'END_M', 'PM', '2025-10-05 12:01:17', NULL),
('2025', 1, 'attendance', 'ATTENDANCE_EDIT_DAYS_BEFORE', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'attendance', 'ATTENDANCE_EDIT_DAYS_AFTER', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'grades', 'GRADES_DOES_LETTER_PERCENT', '0', '2025-10-05 12:01:17', NULL),
('2025', 1, 'grades', 'GRADES_HIDE_NON_ATTENDANCE_COMMENT', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'grades', 'GRADES_TEACHER_ALLOW_EDIT', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'grades', 'GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT', 'Y', '2025-10-05 12:01:17', NULL),
('2025', 1, 'grades', 'GRADES_DO_STATS_STUDENTS_PARENTS', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'grades', 'GRADES_DO_STATS_ADMIN_TEACHERS', 'Y', '2025-10-05 12:01:17', NULL),
('2025', 1, 'students', 'STUDENTS_USE_BUS', 'Y', '2025-10-05 12:01:17', NULL),
('2025', 1, 'students', 'STUDENTS_USE_CONTACT', 'Y', '2025-10-05 12:01:17', NULL),
('2025', 1, 'students', 'STUDENTS_SEMESTER_COMMENTS', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'moodle', 'MOODLE_URL', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'moodle', 'MOODLE_TOKEN', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'moodle', 'MOODLE_PARENT_ROLE_ID', NULL, '2025-10-05 12:01:17', NULL),
('2025', 1, 'moodle', 'MOODLE_API_PROTOCOL', 'rest', '2025-10-05 12:01:17', NULL),
('2025', 1, 'food_service', 'FOOD_SERVICE_BALANCE_WARNING', '5', '2025-10-05 12:01:17', NULL),
('2025', 1, 'food_service', 'FOOD_SERVICE_BALANCE_MINIMUM', '-40', '2025-10-05 12:01:17', NULL),
('2025', 1, 'food_service', 'FOOD_SERVICE_BALANCE_TARGET', '19', '2025-10-05 12:01:17', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `program_user_config`
--

CREATE TABLE `program_user_config` (
  `user_id` int NOT NULL,
  `program` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` longtext COLLATE utf8mb4_unicode_520_ci,
  `school_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `program_user_config`
--

INSERT INTO `program_user_config` (`user_id`, `program`, `title`, `value`, `school_id`, `created_at`, `updated_at`) VALUES
(1, 'REST_API', 'USER_TOKEN', 'd4a16f24b5e471b38738a2cf2a88106d', NULL, '2025-10-06 18:44:02', NULL),
(1, 'REST_API', 'READ_ONLY', NULL, NULL, '2025-10-06 18:50:09', NULL),
(1, 'Preferences', 'THEME', 'FlatSIS', NULL, '2026-03-01 21:52:02', '2026-03-01 21:52:11'),
(1, 'Preferences', 'HIGHLIGHT', '#ffffff', NULL, '2026-03-01 21:52:02', NULL),
(1, 'Preferences', 'DATE', '%d %B %Y', NULL, '2026-03-01 21:52:02', NULL),
(1, 'Preferences', 'HIDE_ALERTS', 'N', NULL, '2026-03-01 21:52:02', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comments`
--

CREATE TABLE `report_card_comments` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `course_id` int DEFAULT NULL,
  `category_id` int DEFAULT NULL,
  `scale_id` int DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_comments`
--

INSERT INTO `report_card_comments` (`id`, `syear`, `school_id`, `course_id`, `category_id`, `scale_id`, `sort_order`, `title`, `created_at`, `updated_at`) VALUES
(1, '2025', 1, NULL, NULL, NULL, '1', '^n n\'apprend pas ses leçons', '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(2, '2025', 1, NULL, NULL, NULL, '2', '^n ne fait pas ses devoirs', '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(3, '2025', 1, NULL, NULL, NULL, '3', '^n a une influence positive', '2025-10-05 12:01:17', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_categories`
--

CREATE TABLE `report_card_comment_categories` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `course_id` int DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `rollover_id` int DEFAULT NULL,
  `color` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_codes`
--

CREATE TABLE `report_card_comment_codes` (
  `id` int NOT NULL,
  `school_id` int NOT NULL,
  `scale_id` int NOT NULL,
  `title` varchar(5) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_code_scales`
--

CREATE TABLE `report_card_comment_code_scales` (
  `id` int NOT NULL,
  `school_id` int NOT NULL,
  `title` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_grades`
--

CREATE TABLE `report_card_grades` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `title` varchar(5) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `gpa_value` decimal(7,2) DEFAULT NULL,
  `break_off` decimal(7,2) DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `grade_scale_id` int DEFAULT NULL,
  `unweighted_gp` decimal(7,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_grades`
--

INSERT INTO `report_card_grades` (`id`, `syear`, `school_id`, `title`, `sort_order`, `gpa_value`, `break_off`, `comment`, `grade_scale_id`, `unweighted_gp`, `created_at`, `updated_at`) VALUES
(1, '2025', 1, '10.0', '1', '10.00', '97.50', 'Très bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(2, '2025', 1, '9.5', '2', '9.50', '92.50', 'Très bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(3, '2025', 1, '9.0', '3', '9.00', '87.50', 'Très bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(4, '2025', 1, '8.5', '4', '8.50', '82.50', 'Très bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(5, '2025', 1, '8.0', '5', '8.00', '77.50', 'Bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(6, '2025', 1, '7.5', '6', '7.50', '72.50', 'Bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(7, '2025', 1, '7.0', '7', '7.00', '67.50', 'Bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(8, '2025', 1, '6.5', '8', '6.50', '62.50', 'Assez bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(9, '2025', 1, '6.0', '9', '6.00', '57.50', 'Assez bien', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(10, '2025', 1, '5.5', '10', '5.50', '52.50', 'Passable', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(11, '2025', 1, '5.0', '11', '5.00', '47.50', 'Passable', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(12, '2025', 1, '4.5', '12', '4.50', '42.50', 'Médiocre', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(13, '2025', 1, '4.0', '13', '4.00', '37.50', 'Médiocre', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(14, '2025', 1, '3.5', '14', '3.50', '32.50', 'Médiocre', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(15, '2025', 1, '3.0', '15', '3.00', '27.50', 'Médiocre', 1, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(16, '2025', 1, '2.5', '16', '2.50', '22.50', 'Insuffisant', 1, NULL, '2025-10-05 12:01:29', NULL),
(17, '2025', 1, '2.0', '17', '2.00', '17.50', 'Insuffisant', 1, NULL, '2025-10-05 12:01:29', NULL),
(18, '2025', 1, '1.5', '18', '1.50', '12.50', 'Insuffisant', 1, NULL, '2025-10-05 12:01:29', NULL),
(19, '2025', 1, '1.0', '19', '1.00', '7.50', 'Insuffisant', 1, NULL, '2025-10-05 12:01:29', NULL),
(20, '2025', 1, '0.5', '20', '0.50', '2.50', 'Insuffisant', 1, NULL, '2025-10-05 12:01:29', NULL),
(21, '2025', 1, '0.0', '21', '0.00', '0.00', 'Insuffisant', 1, NULL, '2025-10-05 12:01:29', NULL),
(22, '2025', 1, 'I', '22', '0.00', '0.00', 'Incomplet', 1, NULL, '2025-10-05 12:01:29', NULL),
(23, '2025', 1, 'N/D', '23', NULL, NULL, NULL, 1, NULL, '2025-10-05 12:01:29', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `report_card_grade_scales`
--

CREATE TABLE `report_card_grade_scales` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `hhr_gpa_value` decimal(7,2) DEFAULT NULL,
  `hr_gpa_value` decimal(7,2) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `gp_scale` decimal(7,2) NOT NULL,
  `gp_passing_value` decimal(7,2) NOT NULL,
  `hrs_gpa_value` decimal(7,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_grade_scales`
--

INSERT INTO `report_card_grade_scales` (`id`, `syear`, `school_id`, `title`, `comment`, `hhr_gpa_value`, `hr_gpa_value`, `sort_order`, `rollover_id`, `gp_scale`, `gp_passing_value`, `hrs_gpa_value`, `created_at`, `updated_at`) VALUES
(1, '2025', 1, 'Principale', NULL, NULL, NULL, '1', NULL, '10.00', '5.00', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29');

-- --------------------------------------------------------

--
-- Table structure for table `resources`
--

CREATE TABLE `resources` (
  `id` int NOT NULL,
  `school_id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `link` text COLLATE utf8mb4_unicode_520_ci,
  `published_profiles` text COLLATE utf8mb4_unicode_520_ci,
  `published_grade_levels` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `resources`
--

INSERT INTO `resources` (`id`, `school_id`, `title`, `link`, `published_profiles`, `published_grade_levels`, `created_at`, `updated_at`) VALUES
(1, 1, 'Imprimer manuel utilisateur', 'Help.php', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(2, 1, 'Guide de configuration rapide', 'https://www.rosariosis.org/fr/quick-setup-guide/', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(3, 1, 'Forum', 'https://www.rosariosis.org/forum/t/francais', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(4, 1, 'Contribuer', 'https://www.rosariosis.org/fr/contribute/', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(5, 1, 'Signaler un bug', 'https://gitlab.com/francoisjacquet/rosariois/-/issues', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `schedule`
--

CREATE TABLE `schedule` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `student_id` int NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date DEFAULT NULL,
  `modified_by` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_id` int NOT NULL,
  `course_period_id` int NOT NULL,
  `mp` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `marking_period_id` int DEFAULT NULL,
  `scheduler_lock` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `schedule_requests`
--

CREATE TABLE `schedule_requests` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `request_id` int NOT NULL,
  `student_id` int NOT NULL,
  `subject_id` int DEFAULT NULL,
  `course_id` int DEFAULT NULL,
  `marking_period_id` int DEFAULT NULL,
  `priority` int DEFAULT NULL,
  `with_teacher_id` int DEFAULT NULL,
  `not_teacher_id` int DEFAULT NULL,
  `with_period_id` int DEFAULT NULL,
  `not_period_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `schools`
--

CREATE TABLE `schools` (
  `syear` decimal(4,0) NOT NULL,
  `id` int NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `address` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `city` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `state` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `zipcode` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `phone` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `principal` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `www_address` text COLLATE utf8mb4_unicode_520_ci,
  `school_number` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `reporting_gp_scale` decimal(10,3) DEFAULT NULL,
  `number_days_rotation` decimal(1,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `schools`
--

INSERT INTO `schools` (`syear`, `id`, `title`, `address`, `city`, `state`, `zipcode`, `phone`, `principal`, `www_address`, `school_number`, `short_name`, `reporting_gp_scale`, `number_days_rotation`, `created_at`, `updated_at`) VALUES
('2025', 1, 'الفرقان لتعليم القرآن بمساكن ', 'نهج الأندلس طريق 30 مساكن Msaken, Tunisia', 'Sousse', 'Msaken', '4013', NULL, 'M. Principal', 'https://www.facebook.com/profile.php?id=61579903807905', NULL, NULL, '10.000', NULL, '2025-10-05 12:01:13', '2025-10-05 12:23:38');

-- --------------------------------------------------------

--
-- Table structure for table `school_fields`
--

CREATE TABLE `school_fields` (
  `id` int NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `school_gradelevels`
--

CREATE TABLE `school_gradelevels` (
  `id` int NOT NULL,
  `school_id` int NOT NULL,
  `short_name` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `title` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `next_grade_id` int DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_gradelevels`
--

INSERT INTO `school_gradelevels` (`id`, `school_id`, `short_name`, `title`, `next_grade_id`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 'CP', '_', 2, '1', '2025-10-05 12:01:17', '2026-02-22 16:32:22'),
(10, 1, '3e', 'جزء تبارك', NULL, '1', '2026-02-22 16:13:04', NULL),
(11, 1, '3e', 'جزء عم', NULL, '1', '2026-02-22 16:25:55', NULL),
(12, 1, '3e', 'جزء المجادلة', NULL, '1', '2026-02-22 16:26:14', NULL),
(13, 1, '3e', 'جزء الأحقاف', NULL, '1', '2026-02-22 16:26:28', NULL),
(14, 1, '3e', 'جزء يس', NULL, '1', '2026-02-22 16:26:40', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `school_marking_periods`
--

CREATE TABLE `school_marking_periods` (
  `marking_period_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `mp` varchar(3) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `school_id` int NOT NULL,
  `parent_id` int DEFAULT NULL,
  `title` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `post_start_date` date DEFAULT NULL,
  `post_end_date` date DEFAULT NULL,
  `does_grades` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `does_comments` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_marking_periods`
--

INSERT INTO `school_marking_periods` (`marking_period_id`, `syear`, `mp`, `school_id`, `parent_id`, `title`, `short_name`, `sort_order`, `start_date`, `end_date`, `post_start_date`, `post_end_date`, `does_grades`, `does_comments`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, '2025', 'FY', 1, NULL, 'Année complète', 'Année', '1', '2025-06-13', '2026-06-12', NULL, NULL, NULL, NULL, NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29'),
(2, '2025', 'SEM', 1, 1, 'Semestre 1', 'S1', '1', '2025-06-13', '2025-12-31', '2025-12-28', '2025-12-31', NULL, NULL, NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29'),
(3, '2025', 'SEM', 1, 1, 'Semestre 2', 'S2', '2', '2026-01-01', '2026-06-12', '2026-06-11', '2026-06-12', NULL, NULL, NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29'),
(4, '2025', 'QTR', 1, 2, 'Trimestre 1', 'T1', '1', '2025-06-13', '2025-09-13', '2025-09-11', '2025-09-13', 'Y', 'Y', NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29'),
(5, '2025', 'QTR', 1, 2, 'Trimestre 2', 'T2', '2', '2025-09-14', '2025-12-31', '2025-12-28', '2025-12-31', 'Y', 'Y', NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29'),
(6, '2025', 'QTR', 1, 3, 'Trimestre 3', 'T3', '3', '2026-01-01', '2026-03-14', '2026-03-12', '2026-03-14', 'Y', 'Y', NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29'),
(7, '2025', 'QTR', 1, 3, 'Trimestre 4', 'T4', '4', '2026-03-15', '2026-06-12', '2026-06-11', '2026-06-12', 'Y', 'Y', NULL, '2025-10-05 12:01:13', '2025-10-05 12:01:29');

-- --------------------------------------------------------

--
-- Table structure for table `school_periods`
--

CREATE TABLE `school_periods` (
  `period_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `length` int DEFAULT NULL,
  `start_time` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `end_time` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `block` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `attendance` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_periods`
--

INSERT INTO `school_periods` (`period_id`, `syear`, `school_id`, `sort_order`, `title`, `short_name`, `length`, `start_time`, `end_time`, `block`, `attendance`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, '2025', 1, '1', 'Journée complète', 'JOUR', 300, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(2, '2025', 1, '2', 'Matin', 'AM', 150, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(3, '2025', 1, '3', 'Après-midi', 'PM', 150, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(4, '2025', 1, '4', 'Heure 1', '01', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(5, '2025', 1, '5', 'Heure 2', '02', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(6, '2025', 1, '6', 'Heure 3', '03', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(7, '2025', 1, '7', 'Heure 4', '04', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(8, '2025', 1, '8', 'Heure 5', '05', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(9, '2025', 1, '9', 'Heure 6', '06', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(10, '2025', 1, '10', 'Heure 7', '07', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(11, '2025', 1, '11', 'Heure 8', '08', 50, NULL, NULL, NULL, 'Y', NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `staff`
--

CREATE TABLE `staff` (
  `syear` decimal(4,0) NOT NULL,
  `staff_id` int NOT NULL,
  `current_school_id` int DEFAULT NULL,
  `title` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `first_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `last_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `middle_name` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `name_suffix` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `username` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `password` varchar(106) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `custom_200000001` text COLLATE utf8mb4_unicode_520_ci,
  `profile` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `schools` varchar(150) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `failed_login` int DEFAULT NULL,
  `profile_id` int DEFAULT NULL,
  `rollover_id` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff`
--

INSERT INTO `staff` (`syear`, `staff_id`, `current_school_id`, `title`, `first_name`, `last_name`, `middle_name`, `name_suffix`, `username`, `password`, `email`, `custom_200000001`, `profile`, `schools`, `last_login`, `failed_login`, `profile_id`, `rollover_id`, `created_at`, `updated_at`) VALUES
('2025', 1, 1, NULL, 'Admin', 'Administrateur', 'A', NULL, 'admin', '$6$bf8649e866535cda$dnsHIpPi3N2WMAu7jxuQlGUHM4ns3hOm1NVlTGebk.egZKChanBMt9LYpDhjPKsJzcusSwKQ4uLeF/MRgAvoF1', NULL, NULL, 'admin', ',1,', '2026-03-01 23:09:48', NULL, 1, NULL, '2025-10-05 12:01:13', '2026-03-01 22:09:48'),
('2025', 2, 1, NULL, 'Teach', 'Enseignant', 'T', NULL, 'teacher', '$6$cf0dc4c40d38891f$FqKT6nlTer3ujAf8CcQi6ABIEtlow0Va2p6HYh.M6eGWUfpgLr/pfrSwdIcTlV1LDxLg52puVETGMCYKL3vOo/', NULL, NULL, 'teacher', ',1,', '2026-02-28 23:11:20', NULL, 2, NULL, '2025-10-05 12:01:13', '2026-02-28 22:11:20'),
('2025', 3, 1, NULL, 'Parent', 'Parent', 'P', NULL, 'parent', '$6$947c923597601364$Kgbb0Ey3lYTYnqM66VkFRgJVFDW48cBAfNF7t0CVjokL7drcEFId61whqpLrRI1w0q2J2VPfg86Obaf1tG2Ng1', NULL, NULL, 'parent', NULL, '2025-10-05 13:10:26', 1, 3, NULL, '2025-10-05 12:01:13', '2025-12-16 19:15:03');

-- --------------------------------------------------------

--
-- Table structure for table `staff_exceptions`
--

CREATE TABLE `staff_exceptions` (
  `user_id` int NOT NULL,
  `modname` varchar(150) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `can_use` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `can_edit` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `staff_fields`
--

CREATE TABLE `staff_fields` (
  `id` int NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff_fields`
--

INSERT INTO `staff_fields` (`id`, `type`, `title`, `sort_order`, `select_options`, `category_id`, `required`, `default_selection`, `created_at`, `updated_at`) VALUES
(200000000, 'text', 'Email Address|fr_FR.utf8:Adresse email', '0', NULL, 1, NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(200000001, 'text', 'Phone Number|fr_FR.utf8:Numéro de téléphone', '1', NULL, 1, NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `staff_field_categories`
--

CREATE TABLE `staff_field_categories` (
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `columns` decimal(4,0) DEFAULT NULL,
  `include` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `admin` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `teacher` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `parent` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `none` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff_field_categories`
--

INSERT INTO `staff_field_categories` (`id`, `title`, `sort_order`, `columns`, `include`, `admin`, `teacher`, `parent`, `none`, `created_at`, `updated_at`) VALUES
(1, 'General Info|fr_FR.utf8:Infos générales', '1', NULL, NULL, 'Y', 'Y', 'Y', 'Y', '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(2, 'Schedule|fr_FR.utf8:Emploi du temps', '2', NULL, NULL, NULL, 'Y', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(3, 'Food Service|fr_FR.utf8:Cantine', '3', NULL, 'Food_Service/User', 'Y', 'Y', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30');

-- --------------------------------------------------------

--
-- Table structure for table `students`
--

CREATE TABLE `students` (
  `student_id` int NOT NULL,
  `last_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `first_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `middle_name` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `name_suffix` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `username` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `password` varchar(106) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `failed_login` int DEFAULT NULL,
  `custom_200000000` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000003` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000004` date DEFAULT NULL,
  `custom_200000005` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000006` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000007` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000008` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000009` longtext COLLATE utf8mb4_unicode_520_ci,
  `custom_200000010` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `custom_200000011` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  `custom_200000012` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000013` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000014` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000015` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000016` text COLLATE utf8mb4_unicode_520_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `students`
--

INSERT INTO `students` (`student_id`, `last_name`, `first_name`, `middle_name`, `name_suffix`, `username`, `password`, `last_login`, `failed_login`, `custom_200000000`, `custom_200000003`, `custom_200000004`, `custom_200000005`, `custom_200000006`, `custom_200000007`, `custom_200000008`, `custom_200000009`, `custom_200000010`, `custom_200000011`, `created_at`, `updated_at`, `custom_200000012`, `custom_200000013`, `custom_200000014`, `custom_200000015`, `custom_200000016`) VALUES
(2528, 'الأندلسي', 'محمد عزيز', NULL, NULL, '0x39di9j', '$2y$10$/pVe87NxPjS5B1roh2FCZON9EkGl5NLc79Ele/mSlb3uIZ6dXFxMC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:16', '40 DT', '3901635141', 'محمد أنيس الأندلسي', '9 - 12', '20310150'),
(2529, 'جبالي', 'أيوب', NULL, NULL, '017tripk', '$2y$10$5OnJogsCLp/TfHCSc5UkweEcBNi.yqJwT3wOehvqE9vuZeAhUaoj6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:50', '40 DT', NULL, NULL, '13- 25', '22318400'),
(2530, 'قمحة', 'زينب', NULL, NULL, '8ygcke94', '$2y$10$sOCaO121mTlcdTictU4nx.bcc736LWjWT8GuTIqiWdywjkCcHnWzC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:02', '40 DT', '6516598729', 'مريم قم', '6 - 8', '29369156'),
(2531, 'الأندلسي', 'محمد أنس', NULL, NULL, 'l6c4y9rv', '$2y$10$LJXF4CHB9BLKO2j9OkuCWuhk4u1/K3nksIvnUfSP0Ate6Gw6vGuYu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:16', '40 DT', '1328996996', 'محمد أنيس الأندلسي', '6 - 8', '20310150'),
(2532, 'مارية جرار', 'سلين', NULL, NULL, 'vvu1sidb', '$2y$10$31JvSNQuiftU2jRByVgMX.gAELnZCRKnHoqbdXrNJCpF8Aw7FWHoi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:04', '40 DT', '2745085347', 'محمد جرار', '6 - 8', '52473013'),
(2533, 'شوشان', 'يوسف', NULL, NULL, 'lspioj68', '$2y$10$I5gOibtoSG0XypgOyMkVYOpCyb6PggPpWoRMPU3AF/..Nbh0LfsWC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:55', '40 DT', '4765045615', 'اسامة شوشان', '9 - 12', '23719210'),
(2534, 'شوشان', 'زينب', NULL, NULL, 'bnvzxwzc', '$2y$10$bCCZDC6jTKWmkctBD3yTDuTVPMwO8KnspxwbQ5TtTRqcynFiHPA8G', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:55', '40 DT', NULL, NULL, '13- 25', '23719210'),
(2535, 'بن سيك علي', 'أيمن', NULL, NULL, 'sffhwour', '$2y$10$KUPpp53DKUhHfinj5pRd6ueBK94YZ4nS8Jq/fq4yG4oNAqj7Xa39i', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:40', '40 DT', NULL, NULL, '13- 25', '56603721'),
(2536, 'ضو', 'براهيم', NULL, NULL, 'jd1uk0uw', '$2y$10$09JbmDjcudyaHhuJOox6uuCLvoxJcliOinoG4KKBhfnwDNlSnc/ly', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:56', '40 DT', '9699479655', 'محمد خيري ضو', '6 - 8', '27121471 - 22040971'),
(2537, 'الكعيبي', 'سارة', NULL, NULL, 'vwlpo3r6', '$2y$10$JRQOg7IYbQxRBUXJb8.grOrlunxUfzWpnxVq/blIpdHCqzJA.Y5WW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:32', '40 DT', '2309124810', 'محمد طاهر الكعيبي', '9 - 12', '21153208'),
(2538, 'الأحول', 'عايشة', NULL, NULL, 'ld39f46n', '$2y$10$gufIGNg6olVeyk2iRm/Q3.Yt3L21vSt54bJxPFANQoNgwP1ZVsI2y', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:15', '40 DT', '4003996817', 'محمد الأحول', '9 - 12', '22747749'),
(2539, 'الكعيبي', 'آدم', NULL, NULL, 'tmvbtdam', '$2y$10$ZWJM47/y6qOeLz2WEg0rc.bzHqxfSRzpRj5C9uXS3da8Q37QggGw6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:32', '40 DT', '1798088289', 'محمد الطاهر الكعيبي', '9 - 12', '21153208'),
(2540, 'الأحول', 'محمد موسى', NULL, NULL, 'gv4zml2s', '$2y$10$xisR.0NcDvJ2VOyaqjntCeTjtBRjKC6rkv7rOPIwCp/7VcbEFQuvG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:16', '40 DT', '9243424838', 'محمد  الأحول', '6 - 8', '22747749'),
(2541, 'كريفة', 'زيد', NULL, NULL, 'teqrh18r', '$2y$10$ej20asRADkKcuRxZgKl6Vu6kFjpgU.jDFwmShoI3x49W2KMANERJS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:03', '40 DT', '8478484757', 'عياد كريفة', '9 - 12', '50144872'),
(2542, 'حماد العضروط', 'فاطمة الزهراء', NULL, NULL, 'o91wbyqi', '$2y$10$jiU5GEgNowlu10fORF/nWOj8/ibKsJLL5ejWswjs1tI7w8UOPxmFy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:51', '40 DT', '1072111694', 'عمر  حماد العضروط', '9 - 12', '55783352'),
(2543, 'العضروط', 'نوح محمد', NULL, NULL, 'iynpg2ye', '$2y$10$MBjTjA2Kb.hIV4pQ98ZgauOhbFJZ6gtIctmHfuJaqzR/mPQB0M1Q2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:27', '40 DT', '1229559569', 'عمر حماد العضروط', '6 - 8', '55783352'),
(2544, 'المخينيني', 'ابراهيم', NULL, NULL, 'knj5qo3g', '$2y$10$VUY1XvUiSTzAWhMAw/Bbne90OvpNoX0Rg7WsFwjRQCQAFdNz.oG0y', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:33', '40 DT', '5254489592', 'حسام المخينيني', '6 - 8', '94659763'),
(2545, 'طراد', 'ابراهيم', NULL, NULL, '3nrweqdz', '$2y$10$6wzORWSuPGgwKEY2DY7dEO8iTHjB95osHuN4x0MJdaVULc1ObJhO2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:56', '40 DT', '7955395180', 'أماني رمضان', '9 - 12', '52854455'),
(2546, 'طراد', 'محمد', NULL, NULL, 'qtsrrpex', '$2y$10$n8YGy4nsl1TwviCTogZrK.0KZXugZrnmrbS//sOY2r.CoBPOTyFfS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:56', '40 DT', '6887626658', 'أماني رمضان', '9 - 12', '52854455'),
(2547, 'الغماري', 'سلسبيل', NULL, NULL, 'goorsmip', '$2y$10$RRVMpHfHCgXbCUsp7dEBuOOgQ2ikxSmgVTbQfS57IT2f183dL1Rpq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:29', '40 DT', '3211376431', 'رمزي الغماري', '9 - 12', '25435339'),
(2548, 'براهم', 'إيمان', NULL, NULL, 'zi93diqz', '$2y$10$Av/WuDRayx7/ADNH3FDb2OhK7aMFM/qBGiMuSxQADIWbLAccnlQTu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:35', '40 DT', NULL, NULL, 'فوق 26', '56739303'),
(2549, 'محجوب', 'نصاف', NULL, NULL, 'cnbubl2z', '$2y$10$NHNh2cPM5LMcQQrl6rcLsOKKkcfGqPBugEhDB5dmc6HxDybeBqwB6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:04', '40 DT', NULL, NULL, 'فوق 26', '98624146'),
(2550, 'هميلة', 'نهى', NULL, NULL, 'jss4r9i7', '$2y$10$n9AAIzSCuWIN2UlRs/dz..ifeNo9jhBatf0/Lcl2Nvbo3sanAf6DK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '93425023'),
(2551, 'كشيش', 'محمد', NULL, NULL, 'lequgqj4', '$2y$10$.N.dW4ePob.QIUMKVDHUT.bW4pkfcKPjFR4kGa8aT94Z9luw0ezAi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:03', '40 DT', NULL, NULL, '13- 25', '54667004'),
(2552, 'بوهلال', 'سوسن', NULL, NULL, '1pi70shw', '$2y$10$3tsnThiBjqjeR3irL2rhQOUTo9954M4jIKjWNH3I4bnukt.o6Mt/.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:47', '40 DT', NULL, NULL, 'فوق 26', '97645167'),
(2553, 'بن عبد الجليل', 'رشا', NULL, NULL, '0684nodo', '$2y$10$oWYUJpv9SlrKndGcWTG4C.82.ajzAJuZNXGQa6MDWI0HdPqItciwa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:41', '40 DT', NULL, NULL, 'فوق 26', '98312251'),
(2554, 'موه', 'السيدة', NULL, NULL, 'oe4vomay', '$2y$10$V02wOeZ8LJn4zmaGBYZX5uKQcJoZDwXIiVj5BODZ0eT5T3izz17aC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:05', '40 DT', NULL, NULL, 'فوق 26', '22922964'),
(2555, 'قمحة', 'يوسف', NULL, NULL, 'i4k56boz', '$2y$10$rYeAt3F4xQ6hQ6tQ4zCYy.WiX0.alWvdO9gXxrO8z7My0ZCq6IOQS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:02', '40 DT', NULL, NULL, 'فوق 26', '97311062'),
(2556, 'قريط', 'جميلة', NULL, NULL, 'iiuasec0', '$2y$10$tQv4wKP47CQ1A8hxNx011e2o4E3aE7aykwFkO9ExGm9DWXbS13ltO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:00', '40 DT', NULL, NULL, 'فوق 26', '98481050'),
(2557, 'زاوية', 'بثينة', NULL, NULL, '53ixga7j', '$2y$10$BTINnAMGpsxzubWdWHPdM.w1QzKSKbLDXQiE4ipLiL9efAIgqfOdq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:53', '40 DT', NULL, NULL, 'فوق 26', '52197022'),
(2558, 'لغماري', 'رمزي', NULL, NULL, 'bqx9edya', '$2y$10$Ntle7UvrvntKr/YaocDPbenNA.PgoanV2JGWBOKyz85pf9p4RmMPi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:04', '40 DT', NULL, NULL, 'فوق 26', '25435339'),
(2559, 'كريفة', 'بسمة', NULL, NULL, 'qtji2ad9', '$2y$10$dtBkgEuC1qq3VUJPRCOZQuDHGSJb4oIl1p9R0AoDbMSwHEr9i2Pvq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:03', '40 DT', NULL, NULL, '13- 25', '5599392'),
(2560, 'عابدي', 'ريم', NULL, NULL, '1qdrwbpt', '$2y$10$ShQ1ZBIwdRUg1lf8c7wcBOGW.EfNiFBE1UGW9W.nSPMfbCyBXT.wa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:56', '40 DT', NULL, NULL, 'فوق 26', '97400518 - 95681749'),
(2561, 'بوهلال', 'منى القروي', NULL, NULL, '9n176apc', '$2y$10$EqjPJJMCmvPBPajbPmbzqOjDR.gYqM3zpMo4AWmf9d1BrUjygwLFW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:48', '40 DT', NULL, NULL, 'فوق 26', '41735171'),
(2562, 'هميلة', 'خدوجة', NULL, NULL, 'qmkozfal', '$2y$10$kbGXvMiBQJP2JOvjerU.C.DWSxw/22uDn8sVizAR33Chh8OQxZP5G', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:06', '40 DT', NULL, NULL, 'فوق 26', '41504264'),
(2563, 'جلاصي', 'أمير', NULL, NULL, 'v4ff6s5p', '$2y$10$PNxNWUrV/dxhxh8uDuZq6OP.C4L/VSDnE2nRKU6Jzdfxt6e.nUBfC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:50', '40 DT', NULL, NULL, 'فوق 26', '53390208'),
(2564, 'بن الفقيه احمد', 'مرام', NULL, NULL, 'me6vk5l5', '$2y$10$r40tg6goo6JyyE3CaiQwaOjKhcJs2RZL/UxPbt05LIa1jZ7NGSAci', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:37', '40 DT', NULL, NULL, '13- 25', '28212430'),
(2565, 'قرشان', 'طارق', NULL, NULL, '6j7ap6zs', '$2y$10$M/QhUFb2GavGxufvWv3Ui.4ZgwE78YzzstQCgIOECllRpLRwmVZFa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:59', '40 DT', NULL, NULL, 'فوق 26', '97849888'),
(2566, 'القلعي', 'هاجر', NULL, NULL, 'kyf20i8b', '$2y$10$UaYKnbW2wdCLDXGfABtrqe4DdDCs0jOQ29SaBWp/FaZRBFp6H0XiK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:32', '40 DT', NULL, NULL, 'فوق 26', '99553439'),
(2567, 'بن حسن', 'سعاد', NULL, NULL, 'hc37qcfg', '$2y$10$0VXKRfJwTzuIbxdr2wdOTuRlhFIenHCZ8Or.rL0FK3KyAvBiIhFoC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:38', '40 DT', NULL, NULL, 'فوق 26', '96508073'),
(2568, 'سخانة', 'امال', NULL, NULL, 'rstezjaq', '$2y$10$K6qFswco84wjEjumPhNqi.6GnaGvNzLeKMTXZaSKS1aBeqWNQrZD.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:54', '40 DT', NULL, NULL, 'فوق 26', '58089967'),
(2569, 'بوهلال', 'إيمان', NULL, NULL, 'rbyy4kw0', '$2y$10$yvJWvCny/s8xG1Da73hwxeDGMevxd1gKgKi.L8cgQmkH8t6wDtbsW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:46', '40 DT', NULL, NULL, 'فوق 26', '56145052'),
(2570, 'بوهلال', 'نجاح', NULL, NULL, 'iaysubdp', '$2y$10$8IgRk4JS1EYjuvDQcQgSfOKF3AHVW25G21RlFgHCl0LODoxBukkWa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:48', '40 DT', NULL, NULL, 'فوق 26', '55217328'),
(2571, 'بوهلال', 'سهام', NULL, NULL, 'xdzglfdd', '$2y$10$l5yRSepGxAE5vg0M43cR4ep.AC9/C5IxpWQNJrIdaoT8Tkr/3mQkm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:47', '40 DT', NULL, NULL, 'فوق 26', '53732512'),
(2572, 'عرفة', 'هالة', NULL, NULL, 'r1gy8169', '$2y$10$NGXHC1PbXzXOB3Sr8UA/M.hKOZNAsW8Ibikr7i6lxMGQ83BadMtj6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:57', '40 DT', NULL, NULL, 'فوق 26', '28205450'),
(2573, 'الشرقي الشطي', 'منية', NULL, NULL, '4u22hsct', '$2y$10$.l0dGQfYqRMvPhdrb6bVEu8V2ToqMlHozxc3rjj3LCNkBh05WMfMi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:25', '40 DT', NULL, NULL, 'فوق 26', '24922444'),
(2574, 'عميمي', 'سعاد', NULL, NULL, 'ympvaq43', '$2y$10$0S2Lrl8Kvt5TabaJAsgwleGnqPRS1riX.eA9FEUYS.1/DyhAB4yOq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:14:58', '40 DT', NULL, NULL, 'فوق 26', '53136018'),
(2575, 'موه', 'خولة', NULL, NULL, 'm28qxdsu', '$2y$10$k4buSTtAIt1mJ.B7XLkgvOz0a5vv/G4UxrMMSj5suCrviQRUViHpa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:11:59', '2026-02-28 21:15:05', '40 DT', NULL, NULL, 'فوق 26', '56603721'),
(2576, 'بوهلال', 'صباح', NULL, NULL, 'm7iq1pml', '$2y$10$CNV89j3i9/BGojUxk3sUke2ScY5dJmWfHjVPcTdB6mI6q2I4i2gwe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:47', '40 DT', NULL, NULL, 'فوق 26', '97354336'),
(2577, 'مدلة', 'محمد', NULL, NULL, '7wtxgvcy', '$2y$10$7bO2CycrJtteXF2pPk87keyT9TwsCjUF1fkeLVzqwOLv23ZZi1J3W', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:04', '40 DT', NULL, NULL, '13- 25', '92794460'),
(2578, 'ضيفاوي', 'زهير', NULL, NULL, '15i8tg6g', '$2y$10$7J3svVXkSsEO5OqSS2GNZulwkX2SM7AseHjjb3T0VGm7bNjwpDuIq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:56', '40 DT', NULL, NULL, 'فوق 26', '28432122'),
(2579, 'الغماري', 'أروى', NULL, NULL, 'oa08wmc0', '$2y$10$wu45B7eWpDQ8o8HxNPz8FOr0IQYfWXqu4Eg5UgyX.3a/C17/7kHSm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:28', '40 DT', '9507686483', 'محمد البشير لغماري', '9 - 12', '93507078 - 92118916'),
(2580, 'الغماري', 'أريج', NULL, NULL, 'pz0bw7q7', '$2y$10$l1jrt6q8pPR6fRKQL6bEEOykW0ko7J0os4LLrQMtS/kBLCKgk0HhG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:28', '40 DT', '5382354184', 'محمد البشير لغماري', '9 - 12', '93507078 - 92118916'),
(2581, 'الغماري', 'أيوب', NULL, NULL, '01elutb9', '$2y$10$XO1jW6/WJ/q3eSEaosc5KOsUv3W2YCCGVUuzaxeHLk2JVql3Egv5O', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:28', '40 DT', '1945593462', 'محمد البشير لغماري', '6 - 8', '93507078 - 92118916'),
(2582, 'بورورو', 'جاد', NULL, NULL, 'ypkq8xko', '$2y$10$Kt/.gsTGTslQXZJQ8on8auNXqzHB0z7sKjLhvwQQGOi0lVesNA1p2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:44', '40 DT', '1358376074', 'عاطف بورورو', '6 - 8', '97114000 - 54000634'),
(2583, 'بورورو', 'تيم الله', NULL, NULL, 'ynwg48xp', '$2y$10$sK.BTpzzf5d8S2YIci8hV.KmsCUZ0O0duz5Ju63qfwrZ.BRa5LMMG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:44', '40 DT', '8127017179', 'عاطف بورورو', '9 - 12', '97114000 - 54000634'),
(2584, 'قرشان', 'موسى', NULL, NULL, '9kmyljza', '$2y$10$KHqvYGyM7IwrIisWa8tr4OPJNf4OF29sDUOUs.s9vegNts3wZZo8e', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:59', '40 DT', '3083519458', 'طارق قرشان', '9 - 12', '99553439 - 97849888'),
(2585, 'قرشان', 'يحيى', NULL, NULL, 'wu2pz9v8', '$2y$10$ZeZtYL5.3oqcbYMRlsm/HunxMl.d.l4li6D5gcqdhNZNlgG4u8WQ2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:59', '40 DT', NULL, NULL, '13- 25', '99553439 - 97849888'),
(2586, 'قرشان', 'إسماعيل', NULL, NULL, '6pa8euwx', '$2y$10$SLHBrY3jaHELujeNbMpuce78S2j8p5ubPhx2Adi2OUInhq7IvRLYy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:59', '40 DT', NULL, NULL, '13- 25', '99553439 - 97849888'),
(2587, 'براهم', 'ياسمين', NULL, NULL, '9quje84o', '$2y$10$wsUE4bs.Iypi42j./3xiO.ZgyF4YVqWSoccWAHjH8Fe9JAOXk1jfC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:35', '40 DT', NULL, NULL, '13- 25', '24922444 - 22638517'),
(2588, 'براهم', 'محمد', NULL, NULL, 'klytw3xn', '$2y$10$vrCyO4cM5yllW88cE55hm.huDF00XkVWdC87lnRkO6wu7f5VcPvOC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:35', '40 DT', '8904841082', 'رياض براهم', '6 - 8', '24922444 - 22638517'),
(2589, 'براهم', 'تيسير', NULL, NULL, 'ewq47pj0', '$2y$10$Ysea0zxy1AOO8Tjy.g.P6.23Bw5rS6z.HT/GpT.X5juGd9Ydoer2u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:35', '40 DT', '6893175664', 'رياض براهم', '9 - 12', '24922444 - 22638517'),
(2590, 'هميلة', 'يسر', NULL, NULL, 'q6gb6a9l', '$2y$10$35ducEJ/U/flqWoQVBSzv.D705rvHnlJBGklRjZdDmnFmUobgTRlq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:08', '40 DT', '9644896219', 'رياض هميلة', '9 - 12', '50777895'),
(2591, 'هميلة', 'نور', NULL, NULL, '9loza5s0', '$2y$10$..mN1bfLl9Zjz9/epYZS8OvxPhRdgLOnJ6L73cYESSyEV69OTqdz6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:07', '40 DT', '9703140877', 'رياض هميلة', '6 - 8', '50777895'),
(2592, 'هميلة', 'إياد', NULL, NULL, 'u6khtqw0', '$2y$10$42msY14vmbQt4RR7tGeVM.MsOWKAqSACx.Jx/hLwsODuWfFaThaM6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:06', '40 DT', '3386846542', 'رياض هميلة', '9 - 12', '50777895'),
(2593, 'القابسي', 'كنزة', NULL, NULL, '639k002q', '$2y$10$iCESUIKztO5FUuqQwwizzOLEgPprES0t0OW6aLEsaZvbSdhCFBHXS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:29', '40 DT', '7397040144', 'محمد القابسي', '9 - 12', '95747450 - 97644986'),
(2594, 'القابسي', 'محمد زكرياء', NULL, NULL, 'gkzhsti5', '$2y$10$EcAl3.JHg4fIfoXrCsuuluX6n2J55V6/6.496SbfvLkD2u6bs1Rva', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:29', '40 DT', '8094165202', 'محمد القابسي', '6 - 8', '95747450 - 97644986'),
(2595, 'ضيفاوي', 'محمد صديق', NULL, NULL, 'fajlbniw', '$2y$10$2SBM3VSPDwPNj9UXU8vWMuQ2ra0XOrlXZEuw3udWOkvj4zGh1H4EC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:56', '40 DT', '7126952136', 'زهير ضيفاوي', '6 - 8', '28432122'),
(2596, 'ضيفاوي', 'سلسبيل', NULL, NULL, '4s7vtgpv', '$2y$10$PQosf4X5NdsEjpw4TH95UeTgFjMiS/nGoWf5P60pxiKq1Xbr8JZ3e', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:56', '40 DT', '4952290136', 'زهير ضيفاوي', '9 - 12', '28432122'),
(2597, 'الغماري', 'يوسف', NULL, NULL, 'sghxgjay', '$2y$10$lpFDmLObTdLpbWQ0xgIOReaBPnwqUhZCrXjfW3S8owk8DakFD5iIW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:29', '40 DT', '7948745024', 'محمد ياسين الغماري', '9 - 12', '55996595 - 23322844'),
(2598, 'الغماري', 'آدم', NULL, NULL, '8up6wge9', '$2y$10$T8HVsolpjnphVnROoJM/CeEdmDqHTXw/UbH8bF6Aulv2X/gGmmsYi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:28', '40 DT', '6624651978', 'محمد ياسين الغماري', '9 - 12', '55996595 - 23322844'),
(2599, 'بالحاج سلام', 'سجود', NULL, NULL, '59tv5heb', '$2y$10$oWe1GXgjGwdHxgfaqjxr.e1ERUV3ERnpxCy3edYCnclnQXyluq4TW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:35', '40 DT', '5398016553', 'منى الغماري', '6 - 8', '93063114 - 92510029'),
(2600, 'التيس', 'مريم', NULL, NULL, 'scj74erx', '$2y$10$QkrHie5UbNFVWbmOw.dTY.bhMuCQHLsRx3/Zkd03dpVsYq8NHrpyq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:19', '40 DT', '8250910752', 'بشير التيس', '9 - 12', '50531074'),
(2601, 'قليم', 'عمر', NULL, NULL, 'jf7ahb3o', '$2y$10$CMji1ESF1afWvQ7b70Td5.SIwdyfnnebniKxU8jKiA6XwmcbOUns.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:02', '40 DT', '9687290168', 'منذر قليم', '9 - 12', '98793571'),
(2602, 'مريزق', 'أبي', NULL, NULL, 'upt7m0tx', '$2y$10$dVnGzaEiB6pgpT18mpcDTOuLBM2kcgYLrVXPBWdIpcXxiSk8VniWS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:04', '40 DT', '5779568982', 'حسام مريزق', '6 - 8', '96455444 -  96720917'),
(2603, 'غني', 'بشرى', NULL, NULL, '0gerghb8', '$2y$10$4yrGa3FaAki7f8WB9N1JK.AylJQgw5Ef9i4w5eltrl/fuPrBgM5bu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:59', '40 DT', '1614591975', 'نزيهة ذكار', '6 - 8', '23422013'),
(2604, 'الزناقي', 'وئام', NULL, NULL, '8lz2oak0', '$2y$10$9ahK3UVCaN7ib2bnx6vm1.xgETItquYvZLQAKUXxJXjKerggwJWDO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:23', '40 DT', '7777942774', 'حدي بن بلقاسم', '9 - 12', '28052958'),
(2605, 'القزاح', 'أمجد', NULL, NULL, '6098f5tv', '$2y$10$Muc05kVwJyGYigxaTzl.Yu.qDCu5EMyckVKgYJwIgvgX4BBy3Wu.q', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:30', '40 DT', '3604887990', 'أسماء القزاح', '9 - 12', '52149390'),
(2606, 'قريرة الخذيري', 'ياسين', NULL, NULL, 'gx1j0fh6', '$2y$10$B34RcDHC9R/bWhn4YyuE3uAeSEBCB7zVRk7C242DRdnw91dAKj132', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:00', '40 DT', NULL, NULL, '13- 25', '98558879'),
(2607, 'بن سيك علي', 'مرام', NULL, NULL, '8y0fzict', '$2y$10$LCdpleQES.KqKqYog5CdOeDMV4I/4R7pI45OoQ9YNnj9OawE6Md9y', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:41', '40 DT', NULL, NULL, '13- 25', '56603721'),
(2608, 'الجلاصي موسى', 'سلمى', NULL, NULL, 'gmiev5lm', '$2y$10$r6PbT0FecgP5lOK6xe7ECeIkKmSkXA30XD3F7Pz8lLXzUsKwaexIm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:20', '40 DT', '4818489245', 'جمال الجلاصي موسى', '6 - 8', '97239778'),
(2609, 'الجلاصي موسى', 'اسماعيل', NULL, NULL, 'yo9ld2uv', '$2y$10$VzLb8sYYWeTM8ceB2JKNs..t1bnU.Nrc4iGBvtyDdPDbOvNqo0btO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:20', '40 DT', '3840219488', 'جمال الجلاصي موسى', '9 - 12', '97239778'),
(2610, 'الجلاصي موسى', 'آدم', NULL, NULL, 'p4gylji2', '$2y$10$RgicFQHU//ibX3Y2vZn1S.yYSJCwY14ZdSFpIhdo0us2cV/6b/pza', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:20', '40 DT', '6954148248', 'جمال الجلاصي موسى', '9 - 12', '97239778'),
(2611, 'العياشي', 'يحيي', NULL, NULL, 'guf8g9ku', '$2y$10$jDXjgaY0SOhs/nI5JSsYqerDh.KPmmKfh59ku3vKFTLjv9efwpmSm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:27', '40 DT', '9255037455', 'محمد لطفي العياشي', '6 - 8', '28701007/52475110'),
(2612, 'العياشي', 'سليمان', NULL, NULL, 'w92k9rir', '$2y$10$ryPDKCbZROtQqpHjy2NE/uD7QBl6laLtbZQHJClaj3E54ZKa61qbe', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:27', '40 DT', '7953613717', 'محمد لطفي العياشي', '9 - 12', '28701007/52475110'),
(2613, 'العياشي', 'زيد', NULL, NULL, 'n1sb8kew', '$2y$10$BHTvrJX96yxvMdwcW6rdK.psuBCfVyEAKJtmyb37Sc/Zw52F9hX2e', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:27', '40 DT', '6795546614', 'محمد لطفي العياشي', '9 - 12', '28701007/52475110'),
(2614, 'قريط الشطي', 'سارة', NULL, NULL, 'glq9hjry', '$2y$10$8SSUhonZlkgvL6C44g9nNu4qOPLhCT5xvzx5Tp52ePaYt19kglya6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:00', '40 DT', '2298424393', 'محمد احمد قريط الشطي', '9 - 12', '22723411'),
(2615, 'قريط الشطي', 'سيرين', NULL, NULL, '7ptn63k0', '$2y$10$rOvy3WQmO0BcjyrDTp06EuPO0opicP/haBzP6kFRg0d6lZVONLj26', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:15:00', '40 DT', '6392472980', 'محمد احمد قريط الشطي', '9 - 12', '22723411'),
(2616, 'القارص', 'مهند', NULL, NULL, 'qbadhpl2', '$2y$10$NVFDnsCZAxNe3XRsCu.K9uwZDY4uju9WIFZ5uf998k5rJZk5LruNe', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:30', '40 DT', NULL, NULL, '13- 25', '52089410'),
(2617, 'القارص', 'رنيم', NULL, NULL, 'yhnubs9z', '$2y$10$21PeLV1aHqQkSOIRRXJtb.csGuV6buijrGybNPUv1ry3JJ8b7ABma', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:30', '40 DT', NULL, NULL, '13- 25', '52089410'),
(2618, 'الماجري', 'ريان', NULL, NULL, '00lwovsz', '$2y$10$CoWbzF3yevkkU9IrGEwNCOx/E2KI9AOCOVnesFu7YrqHqo4Zq2bs6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:32', '40 DT', '1051551233', 'محمد الماجري', '6 - 8', '28983120'),
(2619, 'جياب', 'شيماء', NULL, NULL, 'y8nfodpm', '$2y$10$7RM5z1zsjkN1dR8lz4izX.jOr7vuMEJiFK09UMvQI9HCSTsTvKdDG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:00', '2026-02-28 21:14:51', '40 DT', '3450311420', 'رحاب الزاوية / رضا جياب', '9 - 12', '55432709 / 51058361'),
(2620, 'جياب', 'ايد', NULL, NULL, '0vjh1lr0', '$2y$10$karqDmqGtrcUX7TjbpGAf.63Ogdziy.YkWQn5hCqBhJ1IXikFLSSu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:51', '40 DT', '6861545276', 'رحاب الزاوية / رضا جياب', '9 - 12', '55432709 / 51058361'),
(2621, 'هميلة', 'آية', NULL, NULL, '7dwxcqki', '$2y$10$evcm9DECLBlAeJjrMdBy5Ol2lWIp5VJfc2q0wBhc2E1ymO6T6tF3W', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:06', '40 DT', '7490796606', 'صابر هميلة', '6 - 8', '97597083'),
(2622, 'بوهلال', 'بشير', NULL, NULL, '8qbuwv27', '$2y$10$jPGN/jQ9WZJmeTjnz1vOy.l9TI3x7hI9IALvu8TRrpPp.SCLTxQc2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:46', '40 DT', '1401317166', 'محمد بوهلال', '9 - 12', '99420384/ 98420383'),
(2623, 'الهويمل', 'اسيل', NULL, NULL, 'a2xkfw3d', '$2y$10$6YiAns/btzHT4Mc9msa3EeZW2pJG/91iKMF7ztEGoLm/GMOHxLyJi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:34', '40 DT', '7276953235', 'وسيم الهويمل', '6 - 8', '52582880'),
(2624, 'قريط الشطي', 'يسر', NULL, NULL, 'k7yt1an7', '$2y$10$3d/PjaUMWjlq6frJBINO.e.0XzZTsPV9RXtjpM4lKQDQpCXhTUlF6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:00', '40 DT', '9118807524', 'محمد احمد قريط الشطي', '9 - 12', '22723411'),
(2625, 'الدريدي', 'هارون', NULL, NULL, '98m33tzn', '$2y$10$O5JOaOmpG1OVIXrWQSF3mOtguhlct2NPtF6g6HcI7Tl3tTswNtjTe', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:21', '40 DT', '6470495740', 'ايمان بن سيك علي', '9 - 12', '99199756'),
(2626, 'الدريدي', 'احمد', NULL, NULL, 'vf8ektt1', '$2y$10$EVzT0H5nvcfA4ve1Y3CLa.klPt93VXz2r3l8Ug2EdLHe4qIOSjYte', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:21', '40 DT', '9722877044', 'ايمان بن سيك علي', '9 - 12', '99199756'),
(2627, 'المخينيني رشيد', 'ريحان', NULL, NULL, '9cxkfo4z', '$2y$10$gc1GiYck3LF1J1cNkF59JOW7M1XZUPqO/JQL2w7r4uy8h4I2AWR4u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:33', '40 DT', NULL, NULL, '13- 25', '95472104'),
(2628, 'الجلاص موسى', 'اسماء', NULL, NULL, '75rnu8v3', '$2y$10$yAPjZ6f3KRyZ8GIDNFmS3uiHseo9m99jAzhHnotPLsliV6T0JTEz.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:19', '40 DT', NULL, NULL, '13- 25', '97239778'),
(2629, 'جرار', 'ريمان', NULL, NULL, '4r96z958', '$2y$10$T.qpH0ukZ1QFpImzupnf2OcuOadZMjU1O7JPTftpllzsepqC53g/K', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:50', '40 DT', '6585168524', 'خالد جرار', '9 - 12', '27242772'),
(2630, 'جرار', 'رتاج', NULL, NULL, '66dl3k21', '$2y$10$puO1S8YcSAZ8vdpk5xT.gu.M/gzTKxvbnfsYs74cGt3o9O83OH4Jy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:50', '40 DT', '6701746871', 'خالد جرار', '9 - 12', '28972572'),
(2631, 'بوقديدة', 'شهد', NULL, NULL, '6arnycap', '$2y$10$wU5EL/gHdO1qBYievpYaauJNcQCZX4pr9nb/.qzOH2BUEbx9sq8Xy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:45', '40 DT', '7114731344', 'محمد بوقديدة', '6 - 8', '24012822'),
(2632, 'المنصوري', 'لينة', NULL, NULL, 'dwx0b88q', '$2y$10$QvivcrhdHKyoMcV8B468muOZP5Ax66bX/FBp2LTfXW3qIEbegxr2.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:33', '40 DT', '4363743141', 'احمد المنصوري', '6 - 8', '22905069'),
(2633, 'المنصوري', 'ياسمين', NULL, NULL, 'x9djf2ex', '$2y$10$xBkwPxc/lu6NlNE9Ek9ZZuogLdw3ExVtcI6R43jggweLWWYI4t4w2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:34', '40 DT', '4480760335', 'احمد المنصوري', '6 - 8', '22905068'),
(2634, 'قريرة الخذيري', 'حمزة', NULL, NULL, 'tjq8f88s', '$2y$10$k0P3sXY2Cqubf4cDPyvHouKq.TuaCz.rjJLpcccdI5O3isVxD6rZi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:00', '40 DT', '9749916806', 'فتحي قريرة الخذيري', '6 - 8', '98502705'),
(2635, 'قريرة الخذيري', 'اسماء', NULL, NULL, 'n9uwqujd', '$2y$10$pWOrlpo/FAKQNYleomWo9eiEdixyVpD71qYui5Z8KOlrYAXE2PxUC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:00', '40 DT', '4930486253', 'فتحي قريرة الخذيري', '9 - 12', '98502705'),
(2636, 'قريرة الخذيري', 'سلمى', NULL, NULL, 'wb2bsj8b', '$2y$10$SJVwgafncg3DRiWReagQnODn917zCrZ4P5onJq7pYP1LNwEETccgy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:00', '40 DT', '4282232526', 'فتحي قريرة الخذيري', '9 - 12', '98502705'),
(2637, 'بوهلال', 'نهى', NULL, NULL, 'pxbwridi', '$2y$10$QzRkSVm4U5xaVYcAtzltYOFHfd0weDBuSqEmka5nayQnfINbwRoZ.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:48', '40 DT', NULL, NULL, 'فوق 26', '27466836'),
(2638, 'بن حسين', 'هيكل', NULL, NULL, 'gikefqpv', '$2y$10$iue5lmn1AkSDMkZP87Sr5u4rDtxJkgteVgx8nRSFoxAPtxBl0xPNm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:38', '40 DT', NULL, NULL, 'فوق 26', '22668216'),
(2639, 'العابد', 'حمزة', NULL, NULL, 'kstsr23o', '$2y$10$Cjfc68r/TH5bnrbx9hwV0O2Qp/kk1f44Wd05Wn54YpnzHMKBAmIJi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:26', '40 DT', NULL, NULL, 'فوق 26', '51607863'),
(2640, 'يوسف', 'محمد الهادي', NULL, NULL, 'cxnkcvuw', '$2y$10$M/AEi7HqbsZ8svuB0zLNdOI2eyI2g/ujaVcRWfCkEWwaRJl0OyQW.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:08', '40 DT', NULL, NULL, 'فوق 26', '25654539'),
(2641, 'الخياري', 'كوثر', NULL, NULL, 'd3smarcd', '$2y$10$1uplhs.wR/lT5./9qA8vQeZSzGHpH01qvJk3hu/go/VdQbxEV5OxO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:21', '40 DT', NULL, NULL, 'فوق 26', '22750046'),
(2642, 'ابن الحاج الصغير', 'المنجي', NULL, NULL, 'tuoeg87w', '$2y$10$hXp9D3kM7g0iVchIX5R9COy1qn0xPWSCHgT4Mp92YB.H/YmUxmCue', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:14', '40 DT', NULL, NULL, 'فوق 26', '25867073'),
(2643, 'بوهلال', 'منيرة', NULL, NULL, 'sjwha49r', '$2y$10$G2/R6laXyqog/Mpg3MFp9OYPmRNqzIJiok3G7yvqqxB2rufPj.Y72', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:48', '40 DT', NULL, NULL, 'فوق 26', '25647502'),
(2644, 'بن خليفة', 'فراس', NULL, NULL, 'hj0b49cq', '$2y$10$27WcDw1RQlInPP6PK.FQb.TizxT7TWY0fO5YL6QH5gqt1ZLzLNr7a', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:39', '40 DT', NULL, NULL, '13- 25', '50358654'),
(2645, 'حواس', 'سوسن', NULL, NULL, 'nhb2l185', '$2y$10$1ULEq.lVbmytUnNbqImsvuMbeB6mXy/u.Sq5oERkmfFKDybN9/57O', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:52', '40 DT', NULL, NULL, 'فوق 26', '92002531'),
(2646, 'خلف الله', 'احلام', NULL, NULL, '6c8su1kg', '$2y$10$EPkmrJp5nBYEtGE/ZDXBwuc.llfmxtRP/XgqRDdSS0sz/Junq0h/u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:52', '40 DT', NULL, NULL, 'فوق 26', '28545699'),
(2647, 'ابن الحاج الصغير', 'شيراز', NULL, NULL, 'umo0ytqc', '$2y$10$9USDAem/HxpIriCeVkZtbOFlPICwwZblp/96YCRF7B7p6EyyeFz7q', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:14', '40 DT', NULL, NULL, 'فوق 26', '97597083'),
(2648, 'العزالي', 'مروى', NULL, NULL, 'xdxl782q', '$2y$10$s73Wkq0pFRAoRRlL8ipyQ.EhLn7bDitinpDY6I.uxX1PC.URYw09C', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:27', '40 DT', NULL, NULL, 'فوق 26', '28898645'),
(2649, 'رزق الله', 'نهى', NULL, NULL, 'wnokzl4n', '$2y$10$HCTpROE1amYglXC9yE9b1uVzD63KTLw9GI91D2DwPhYGe/02n6skG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:53', '40 DT', NULL, NULL, 'فوق 26', '51040145'),
(2650, 'رويس', 'نسرين', NULL, NULL, 'sqxjp2cp', '$2y$10$MiBVyhrvUFScjpxPkU5OMuEuSj1y38yNpLn8Kq.hln9VWhvM66znO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:53', '40 DT', NULL, NULL, 'فوق 26', '12845163'),
(2651, 'براهم', 'اين', NULL, NULL, 'ch4e7de4', '$2y$10$M08ZV1vA5mThZpIfsEUdKuOAVgb0z3yhLyqjYT6fJgAhtSirnXMkq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:35', '40 DT', NULL, NULL, '13- 25', '26951730'),
(2652, 'هميلة', 'يونس', NULL, NULL, 'rd2mkiet', '$2y$10$sRUIN4Q.YEsE67D5MRhO8uHTbMx3XdC6m2/JlqbluBSu4ukSJgf0q', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:08', '40 DT', '9236114876', 'بسام هميلة', '9 - 12', '28996036'),
(2653, 'هميلة', 'محمد يحي', NULL, NULL, '1f9g6wno', '$2y$10$o3j7k36Mst.QRVt4GK6r.Ost7oNZRulM2ravhEpbDfGrkfFpK2toS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:07', '40 DT', '1785682696', 'أيمن هميلة', '6 - 8', '22334795'),
(2654, 'هميلة', 'هارون', NULL, NULL, 'xnlbqjw5', '$2y$10$TFtsXmXpIfbhSqNoNP6Y.OHfjbQLbvW3GrsxQf8EWJfuNUmsFYne6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:08', '40 DT', '3247806136', 'أيمن هميلة', '6 - 8', '22334795'),
(2655, 'هميلة', 'اسيل', NULL, NULL, '43byv9un', '$2y$10$QQ1w1vJZt9ypi0jn5gRZR.KFtOhzYe5EJwYQbMPRyWI31CEnVxYIa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:15:06', '40 DT', '9712648796', 'أيمن هميلة', '9 - 12', '22334795'),
(2656, 'الخياري', 'صفاء', NULL, NULL, 'fel0qk3p', '$2y$10$zxIYDf94/y3mFA8/dWuKXO2cRwgGPcy1t31/ejWFY5MfMIZo9Cqj.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:20', '40 DT', '4590336252', 'مروى بوهلال', '6 - 8', '23612987'),
(2657, 'الكعيبي', 'آيلان', NULL, NULL, 'b3r4p1xq', '$2y$10$FyZvQu4VB7dpiiu1536cI.4HkmzKfLWYQEZmjVgS0VorokOgHqbOK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:32', '40 DT', '1435203714', 'وليد الكعيبي', '6 - 8', '21513976'),
(2658, 'الشاهد', 'نوران', NULL, NULL, '4xe6s3nk', '$2y$10$dy4m8qTTW2Jo.Otz.r8ZGOXsKXSH1NiHmXjLqlimqR/AOvZI4WIHi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:24', '40 DT', '3768578443', 'نبيل الشاهد', '9 - 12', '98981810'),
(2659, 'الشاهد', 'نورسان', NULL, NULL, '9c95vp65', '$2y$10$h7lMr85fpnqGlSwKO.JDTOzeZzOf9KsabsRG4nJDcE2zXhGpElI6S', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:24', '40 DT', '4440688793', 'نبيل الشاهد', '9 - 12', '98981810'),
(2660, 'الشاهد', 'بيان', NULL, NULL, 'gvohvcff', '$2y$10$4bCMWIk7scX4/og7CgIi0ur56rYFExXqghd3CodARMfQpxD/agN7.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:24', '40 DT', '4341390095', 'نبيل الشاهد', '9 - 12', '98981810'),
(2661, 'الشاهد', 'احمد', NULL, NULL, '5sfepkgx', '$2y$10$hq2tAGdBGndF2AkrUlUXcetDdFBEtI.RD6A1gqhzSFFqwFQyPvQ1.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:24', '40 DT', '7876802346', 'نبيل الشاهد', '6 - 8', '98981810'),
(2662, 'بن سالم', 'سيف الدين', NULL, NULL, 'j2bon9pf', '$2y$10$WjnDSvMLWUMwCUEzjiHL1.akvLGJs62Z8nl3diOY9nMLvlsNCVfQi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:40', '40 DT', '9009841319', 'فتحي بن سالم', '9 - 12', '56750734'),
(2663, 'الجلاصي', 'زينب', NULL, NULL, '8brezizi', '$2y$10$2M1DOATOBc1h8ii8O6l4FOTrRfVua/l84I85aAa5Mu7Rv4rYI7pSK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:19', '40 DT', '1920440756', 'الهادي الجلاصي', '6 - 8', '99222226'),
(2664, 'الجلاصي', 'ملاك', NULL, NULL, 'kssnij1c', '$2y$10$q..EL0RbPl/4ZC7HuCNSW.d8eWLNBaxZTXf2tgjLCRtWDguHaLiyu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:19', '40 DT', '4735786035', 'الهادي الجلاصي', '6 - 8', '99222226'),
(2665, 'علواني', 'عبد الله', NULL, NULL, '1xtjopdz', '$2y$10$a4P5lqGxq.PDkYtFzVH5du/An07kfRQ1eFIl8diP2R.eRyOLUc1Z6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:58', '40 DT', NULL, NULL, '13- 25', '53404503'),
(2666, 'طراد', 'زينب', NULL, NULL, 'ujeck7jn', '$2y$10$4Z7HSbjzsfaD1A3LXrh1sOTsmKKuC6mOoLWxHj8Ym.LVlP/PB963q', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:56', '40 DT', '3241006032', 'اماني رمضان', '9 - 12/ 13-17 (للحالات الخاصة)', '52854455'),
(2667, 'بن عبد الجليل', 'يوسف', NULL, NULL, '4jk3go4t', '$2y$10$fK7HORxMzb8GqV.Eb/lmy.69PGhpAKWK4xjMiltM0nkT3nwxXeJz6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:01', '2026-02-28 21:14:41', '40 DT', '9465438135', 'وسام بن عبد الجليل', '6 - 8', '26029002'),
(2668, 'حميدة', 'أسرار', NULL, NULL, '2d6lf7yw', '$2y$10$dwhuwW4B1sOMn7OzPmao9u3HQpoEg9iqwdpDw02uRYs8Mt07P6DJu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:51', '40 DT', NULL, NULL, '13- 25', '20127944'),
(2669, 'المخنيني', 'لينة', NULL, NULL, 'h15dnvv8', '$2y$10$lhDj1J34k8hxh8IP7ZkkmumehTqNiEV9Zi4y.ryVo25Bxel1n9foi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:33', '40 DT', '6822977976', 'ياسمين موسى', '6 - 8', '58659550'),
(2670, 'بن عبد الله', 'محمد أمين', NULL, NULL, '27gs1422', '$2y$10$Z.2U.PBSH0lP/5PQ4fUAzu/nLpknysHnjWboE9X/zJOS0NxdOxXsG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:42', '40 DT', '7865509425', 'أمل مبروك', '9 - 12/ 13-17 (للحالات الخاصة)', '97847423'),
(2671, 'الأكحل', 'أميمة', NULL, NULL, 'ziremjmg', '$2y$10$2yNHdNIdXOAlOl9zSrrBQOrD95aGeZV2wFNRGy6mOTALED3lq8/sO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:16', '40 DT', '6360160967', 'محمد مصطفى الأكحل', '9 - 12/ 13-17 (للحالات الخاصة)', '92002531'),
(2672, 'يوسف', 'أحمد طه', NULL, NULL, '0vp6d2qv', '$2y$10$aMOGdsVTSWy1YbZ60qrSSuHoXDvC06khh3ps.CXZWbfQe7NBKPumy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:15:08', '40 DT', '3695283809', 'سالم يوسف', '9 - 12/ 13-17 (للحالات الخاصة)', '50281545'),
(2673, 'اسماعيل', 'عبد الله', NULL, NULL, 'rq206flc', '$2y$10$HWAyDVgY39kwzixf5Ic6iej7UugDId2.jrLoJn3quCrTeuI1.9gi6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:15', '40 DT', '2819390579', 'هبة الله بن فقيه علي', '9 - 12/ 13-17 (للحالات الخاصة)', '55102935'),
(2674, 'اسماعيل', 'حنان', NULL, NULL, '9d9byw82', '$2y$10$UcuBVJ4KWIpDwkP89zDhgOH5AogO2FpzzVZV9O1JtvGfLyaWniltG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:15', '40 DT', '2710106238', 'هبة الله بن فقيه علي', '9 - 12/ 13-17 (للحالات الخاصة)', '55102935'),
(2675, 'حفصية', 'مريم', NULL, NULL, 'x04saugt', '$2y$10$yA4roqEL66ROjAwxSSMpp.BdGB5pKuTlJ3pdGe5qoqF.XpBD.Dbry', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:51', '40 DT', NULL, NULL, '13- 25', '50532827'),
(2676, 'حفصية', 'محمد علي', NULL, NULL, 'mu31qig8', '$2y$10$sLRg6qL3FC83WEpD.Da2XeO.NugzfA49WM13Gkz/WhV0dssIDKgq.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:51', '40 DT', '4934687353', 'أحمد حفصية', '9 - 12/ 13-17 (للحالات الخاصة)', '50532827'),
(2677, 'طالبي', 'غسان', NULL, NULL, 'iuqpbjg7', '$2y$10$gGF4OX.zy6IMaxzVyQzjJ.2Y4o4rNlLxgupeySWbskUe5k8gjs27y', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:56', '40 DT', '4955695341', 'وريدة بنحمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '97137923'),
(2678, 'بوشليقة', 'تسنيم', NULL, NULL, 'l70c54g0', '$2y$10$08SikYUtYqUz6X/HAAkJ9uKYoEhF6qC3FZxOxyJe4jJO..ONkvzD6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:44', '40 DT', '7756229225', 'نجيب بوشليقة', '6 - 8', '52028289'),
(2679, 'بوشليقة', 'محمد أحمد', NULL, NULL, 'wo2lbrc3', '$2y$10$dPSMP0MJUymiaVjXoOWoAO2KfGKWCjhigww0mS.QFs5Zzz1cdAwt2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:44', '40 DT', '3098306201', 'نجيب بوشليقة', '6 - 8', '52028289'),
(2680, 'تريعة', 'فاطمة الزهراء', NULL, NULL, 'nvj3e92o', '$2y$10$QrpaOoCNLc37BZrAtwoVo.OGX9nYNhTPPytyZ1P3xlYYQsIqfbM16', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:49', '40 DT', NULL, NULL, '13- 25', '53847126'),
(2681, 'تريعة', 'نور', NULL, NULL, '149vzbs8', '$2y$10$LYAiZW3dS9Q2Ea/nF31td.wvRkkK/vIq9qVqe9zTxlvTsgKaXCcP.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:49', '40 DT', '4589817607', 'محمود تريعة', '9 - 12/ 13-17 (للحالات الخاصة)', '53847126'),
(2682, 'التكوري', 'عائشة', NULL, NULL, 'nza2yvqg', '$2y$10$D80iq8Q.wEtxa36Tv7WKxOqAyWJp9LtUB0j03MQUjPObgoy2r68vm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:19', '40 DT', '9474346371', 'سمير التكوري', '9 - 12/ 13-17 (للحالات الخاصة)', '20195928'),
(2683, 'التكوري', 'سارة', NULL, NULL, 'rz2z93bq', '$2y$10$07W4kkUKzFaK6kzkZBG.c./btAhYoxiRxj.37A8xSHC1O1NG3Y8hW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:18', '40 DT', '4517139749', 'سمير التكوري', '9 - 12/ 13-17 (للحالات الخاصة)', '20195928'),
(2684, 'التكوري', 'ابراهيم', NULL, NULL, 'r9p9e1xe', '$2y$10$upFmGNV/ivE7Z2GY4Q/NIub/ioueJilnyqsB32oIny57C7wXtlhxu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:18', '40 DT', '3382781030', 'سمير التكوري', '6 - 8', '20195928'),
(2685, 'الخذيري قريرة', 'حسام', NULL, NULL, '472p3zu7', '$2y$10$9DFgV3Ohyk.H7wWj8asOT.uS8q84eJlrymfc/vy9yBQoNkOxeDF8q', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:20', '40 DT', '2971921463', 'محمد الحبيب الخذيري قريرة', '9 - 12/ 13-17 (للحالات الخاصة)', '99483251'),
(2686, 'القارص', 'أنس', NULL, NULL, 'vvarrhga', '$2y$10$DdlGuXomIGhO9HKOX3LpWOE4jKKuTH7f/QRBUW//FgTjV28JXk9j2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:29', '40 DT', '2743726135', 'مالك القارص', '6 - 8', '99133372'),
(2687, 'ابراهيم', 'جنة', NULL, NULL, 'es6uyav8', '$2y$10$BkWP9eUsE4ENNJq6NYSEDe5DYvkveJB4yDC4WCt8kimeL4RJk8TjK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:14', '40 DT', '1619825638', 'ياسين ابراهيم', '6 - 8', '73259007'),
(2688, 'ابراهيم', 'أحمد مؤمن', NULL, NULL, '3nb26mp0', '$2y$10$nOsmTFrONnp.bY/MuqQRf.0tc7PKMw.L5ZBgaw7kVQF6Vdd0.7a2.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:14', '40 DT', '4391657418', 'ياسين ابراهم', '9 - 12/ 13-17 (للحالات الخاصة)', '73259007'),
(2689, 'الزرقاطي', 'زيد', NULL, NULL, '2h5u2pkj', '$2y$10$FJqsLJ.WthYSedwdotLH5O2RtTxZMIUkguhfu6PiE5NV2sDNlfgB6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:22', '40 DT', '2789538696', 'عز الدين الزرقاطي', '6 - 8', '24169895'),
(2690, 'الزرقاطي', 'يامن', NULL, NULL, 'xwjt6hh2', '$2y$10$WEvYMAnfD1SD/JPLcGzLW.8LoBPxGQWuyf4Y.E1RIrANJoYC8wi3e', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:22', '40 DT', '6733957529', 'عز الدين الزرقاطي', '6 - 8', '24169895'),
(2691, 'العابد', 'محمد علي', NULL, NULL, 'got1q15g', '$2y$10$8bR05v.rCvjFAf5BYEnmZeTJcYm1ikyXWqQnF4gcdsarLV9/kVkCa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:26', '40 DT', NULL, NULL, '13- 25', '52677913'),
(2692, 'بن سيك علي', 'كنزة', NULL, NULL, '6d55ofl4', '$2y$10$JYegPgenU/ZL7nk916SKOOqpZ/Kd9WBX52E6B7Be3yWrsMjavEeFO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:40', '40 DT', '6649790944', 'وجدي بن سيك علي', '9 - 12/ 13-17 (للحالات الخاصة)', '26558590'),
(2693, 'بن سيك علي', 'اياد', NULL, NULL, 'ch4aturw', '$2y$10$wWBfHVIPKvzREQ1gu5SGjebqvMvda2ADXx7BLVAmkyNptFl62LZrC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:40', '40 DT', '7275383451', 'وجدي بن سيك علي', '6 - 8', '26558590'),
(2694, 'تريعة', 'ياسمين', NULL, NULL, 'u7rdymqs', '$2y$10$XaJDOtHqhOQzB/yyhPslc.twZE0Hn3.A.J9A7/.4C98PEO0qANpO6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:49', '40 DT', '4363788611', 'رشاد تريعة', '9 - 12/ 13-17 (للحالات الخاصة)', '96451172'),
(2695, 'تريعة', 'سرين', NULL, NULL, 'he657gts', '$2y$10$qWZ5x/SkVK6mgqXVnbdO9.yF0vo/91vZJuhtgKvWzbAP9RjEyAc.O', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:49', '40 DT', '2192608006', 'رشاد تريعة', '9 - 12/ 13-17 (للحالات الخاصة)', '96451172'),
(2696, 'تريعة', 'أدم', NULL, NULL, 'j41a6fy2', '$2y$10$usoaLdrdTObmTMngwyScq.mlu6o5bfJnVIqm94n6M6LTVwJx8mvWm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:49', '40 DT', '6950556420', 'رشاد تريعة', '6 - 8', '96451172');
INSERT INTO `students` (`student_id`, `last_name`, `first_name`, `middle_name`, `name_suffix`, `username`, `password`, `last_login`, `failed_login`, `custom_200000000`, `custom_200000003`, `custom_200000004`, `custom_200000005`, `custom_200000006`, `custom_200000007`, `custom_200000008`, `custom_200000009`, `custom_200000010`, `custom_200000011`, `created_at`, `updated_at`, `custom_200000012`, `custom_200000013`, `custom_200000014`, `custom_200000015`, `custom_200000016`) VALUES
(2697, 'قليصة', 'عائشة', NULL, NULL, 'wiifwsna', '$2y$10$G8qVyay3wE2hGciMdLySBOqtt79eeFiLuk2EfEhPaaYvUXUgLK54O', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:15:02', '40 DT', '8343512792', 'سمية براهم', '6 - 8', '23590193'),
(2698, 'قليصة', 'خديجة', NULL, NULL, 'cxidxf08', '$2y$10$1sSUgw04LAFDJywV88946u7aeVWm2csr5N.kIz/9xO.QLBiYhK2Zy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:15:01', '40 DT', '4043611893', 'سمية ابراهم', '6 - 8', '23590193'),
(2699, 'كرموص', 'ابراهيم', NULL, NULL, 'zh8njtcz', '$2y$10$dZcyuzlUmUdZ25HrsawqROXEni40cz7gnh/iASqGrxgIhSyJiT1QK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:15:02', '40 DT', '3513744063', 'وليد بن صالح كرموص', '6 - 8', '23632423'),
(2700, 'كرموص', 'ادريس صالح', NULL, NULL, 'm131xtgz', '$2y$10$dt4wQqazOFEfJmjcqjUMMenwZcE4WonDVBJOOEnZH94WZ2aYKa8y2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:15:02', '40 DT', '2455541054', 'وليد بن صالح كرموص', '9 - 12/ 13-17 (للحالات الخاصة)', '23632423'),
(2701, 'هميلة', 'شهد', NULL, NULL, '4l6je9mc', '$2y$10$4kapOucrGqxSE.og8RydVOgHMHS8gcy0y6RtD/SOY6g3VLA3IBUK.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:15:07', '40 DT', '4147481439', 'مريم هميلة', '6 - 8', '22254597'),
(2702, 'هميلة', 'يوسف', NULL, NULL, 'g25e2ouq', '$2y$10$HmTobWy2Mv03u7KyuWAwheTnod3t85M38MnBY0U4ywYY88UX5pDL.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:15:08', '40 DT', '5590921564', 'سوسن هميلة', '6 - 8', '96345445'),
(2703, 'حسون', 'محمد الحبيب', NULL, NULL, '5vtni83d', '$2y$10$6TosG5MRL65v0EXEmsWKeekbeYihsMFGrtfZgwCRM1HdmhubvDOoK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:51', '40 DT', '3095003652', 'رياض حسون', '9 - 12/ 13-17 (للحالات الخاصة)', '98452453'),
(2704, 'العيوني', 'أدم', NULL, NULL, 't0pz4zcs', '$2y$10$XCw0lqLj1gv/N/N/9tktUOVkswgVHB.qXVc48MrxLD2Mj9P/yi1vy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:27', '40 DT', '6998018924', 'محمد العيوني', '9 - 12/ 13-17 (للحالات الخاصة)', '99229155'),
(2705, 'العيوني', 'احمد', NULL, NULL, '1mgakncq', '$2y$10$PgrH/xfIpL5Iko7JNAwqKOHKkrojiWS/zsBlOcjKBTy7e6hpWLWdS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:27', '40 DT', '2138819381', 'محمد العيوني', '9 - 12/ 13-17 (للحالات الخاصة)', '99229155'),
(2706, 'العيوني', 'امنة', NULL, NULL, 'yughg9mx', '$2y$10$JQaZ/DWTJKIaOyjhTqoSZO6q.TGnP5ioRxMZJ.hWp3vXCkSal9j8e', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:28', '40 DT', '7859040434', 'محمد العيوني', '9 - 12/ 13-17 (للحالات الخاصة)', '99229155'),
(2707, 'الخذيري قريرة', 'احمد هارون', NULL, NULL, '5b2yvmbx', '$2y$10$8WeKb2Rf2GdP2KQTIz9ts.P7/mPpnXea9sJvyVriTI8CfldGqT8jG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:20', '40 DT', '5173473677', 'محمد الحبيب الخذيري قريرة', '6 - 8', '99483251'),
(2708, 'بن سالم', 'ياسمين', NULL, NULL, 'ywl4auc7', '$2y$10$CHrIyZeOUsLoOOzuiNZJA.mvhqNEdicmoYVnBM2jQE5FQ9ZgJGp/C', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:40', '40 DT', '9830416193', 'فتحي بن سالم', '9 - 12/ 13-17 (للحالات الخاصة)', '56750734'),
(2709, 'زقر', 'ريان', NULL, NULL, '5csorcvu', '$2y$10$.K4tOjr7vHls/yI.P1OCue19tQKqU8fspW8G9UfUurGPBQv33m.yS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:54', '40 DT', NULL, NULL, '13- 25', '99430072'),
(2710, 'رويس', 'محمد معتز', NULL, NULL, '716cxmi6', '$2y$10$3qpk/4Uxuq32l20g8TdPjuCQ1KSDWspVIeTMgUFSzzkQztXgHslhe', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:53', '40 DT', NULL, NULL, '13- 25', '24433789'),
(2711, 'بوشليقة', 'نجيب', NULL, NULL, 'ibp9bwbh', '$2y$10$TxTu1yhgyuqAparF7DruxuONMsPRZiunfikO6wdbluf7M/CPkwnou', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:44', '40 DT', NULL, NULL, 'فوق 26', '97115496'),
(2712, 'المبروك', 'امل', NULL, NULL, 'l8z39jsg', '$2y$10$VVDgTcQwUaP5csLaHPPvy.ngkl1oekcmaZ0qsoworMGn3N/dKeo4O', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:02', '2026-02-28 21:14:32', '40 DT', NULL, NULL, 'فوق 26', '97847423'),
(2713, 'القزاح', 'جميلة', NULL, NULL, 'vw8f6kn5', '$2y$10$zd7STKIc3rxrT7nrzPUqAOXBHvrv5bD/XSkAL/PtynWZ5IqfjPLse', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:31', '40 DT', NULL, NULL, 'فوق 26', '55332212'),
(2714, 'قرع', 'نور', NULL, NULL, '31jogxxq', '$2y$10$RNMRn377lIA8SVz1anOFCeAwKC5xjLiOyVAz2wOxMV5kN8S1GimQ2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:00', '40 DT', NULL, NULL, '13- 25', '20881019'),
(2715, 'بن عبد الجليل', 'فوزية', NULL, NULL, 'pxiky6si', '$2y$10$iaRajYCsQWp3TMi4x2ZqienxFqyI0ut0VdFj/rY9S1ESF80Q5cnBa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:41', '40 DT', NULL, NULL, 'فوق 26', '54096626'),
(2716, 'زقر', 'ياسين', NULL, NULL, 'npci6up7', '$2y$10$d0Apd7ql5pPrm8f9CKVgr.C4xKXkwvhV4VyMjj1YaCw/o/7mDO4Am', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:54', '40 DT', NULL, NULL, 'فوق 26', '56666582'),
(2717, 'قليم', 'شادي', NULL, NULL, '8o9abadv', '$2y$10$JhW3MyAEB734f0vY5HYTqeQyxBXLKQQxj6g8q5gpYxqzKHL7DLHBK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:02', '40 DT', NULL, NULL, '13- 25', '24401607'),
(2718, 'بلحاج جراد', 'مصطفى', NULL, NULL, '02rhvkvo', '$2y$10$YE39YHKG0GkuWJoNd/stW.HQPMG3pg34SoUnojRRk/hDPYktPxjcC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:36', '40 DT', NULL, NULL, '13- 25', '29904233'),
(2719, 'جماقر', 'يوسف', NULL, NULL, 'dxejxub6', '$2y$10$WgfEyIJTWX3DTuW1kRCWDuyeWlnGagk3FPRwv5vlP82gpX/bj1LIq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:50', '40 DT', NULL, NULL, '13- 25', '24879681'),
(2720, 'الرقيق', 'تسنيم', NULL, NULL, 'tfcr0883', '$2y$10$I.pAdIOkNjDhwjC.yJJwa.nt1T9MlVSfAI45XPAI.6oP674AUjqqe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:21', '40 DT', '3132863257', 'مريم ذكار', '6 - 8', '58616647'),
(2721, 'القصير', 'شهد', NULL, NULL, 'z8b7s4q3', '$2y$10$Va3NTi/ZnCwhPxd6B7eieuHODmYbDuh3Ktvj9CjsMkur4NlKbEopi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:31', '40 DT', '1002893104', 'محمد القصير', '6 - 8', '23670740'),
(2722, 'البحري', 'ثريا', NULL, NULL, 'vq01i38n', '$2y$10$kr28EnzOVdPXfT1v.I8HbebRVCQqNwyS545lF3W6Ka6XpuS2shfQO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:17', '40 DT', NULL, NULL, 'فوق 26', '21112525'),
(2723, 'ابن عبد الله', 'نجيب', NULL, NULL, 'xqtbrdam', '$2y$10$thC8Q5HOxWkZe2Z3hgzsCejiYD9LEEAaJKcvYfamEqdVQibnftIFq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:15', '40 DT', NULL, NULL, 'فوق 26', '21103385'),
(2724, 'اليوسفي', 'هاجر', NULL, NULL, 'uf8x86ec', '$2y$10$w0Kt0N0GIOTcEbG2bmaATuR.F1KJfpDFgdrxYidhZny8L0rGX9S/q', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:35', '40 DT', NULL, NULL, 'فوق 26', '28440881'),
(2725, 'كاهية', 'منال', NULL, NULL, 'm36wf4o7', '$2y$10$j3cu.sZAawUd54aYo8/.OOcoFigHgdNS6b7E69MuHQGYeqaOPEHuq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:02', '40 DT', NULL, NULL, 'فوق 26', '99965897'),
(2726, 'النوري', 'اخلاص', NULL, NULL, 'tvsx52ot', '$2y$10$rwwoKmnC//jt25.v4lVMMeIChvcm6LQXGPcGqZO.aTkwggXZznEmq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:34', '40 DT', NULL, NULL, 'فوق 26', '52028289'),
(2727, 'هميلة', 'ايناس', NULL, NULL, 'y0o4zdk7', '$2y$10$uALPFUCxtgk/z7eOB9ZXSORXyzELpXjyn7.zUo3qwxIrNImbCA7hy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:06', '40 DT', NULL, NULL, 'فوق 26', '99229155'),
(2728, 'الحاج عمار', 'كريم', NULL, NULL, '45zskh6n', '$2y$10$EYf1ByXi2.fE4XXIXR/S1e5FmSE7CBajcx03BZz8nB1/LPsmJ3Y3G', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:20', '40 DT', NULL, NULL, '13- 25', '51209546'),
(2729, 'عوني', 'منجية', NULL, NULL, 'z0stl5ba', '$2y$10$fvAPy9ekrYhRlhEXhicwA.zUf6fp0NgWoBXaoGRXXlTjR3xfrs3HC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:58', '40 DT', NULL, NULL, 'فوق 26', '29422352'),
(2730, 'كوادة', 'رضية', NULL, NULL, 'luor2hjj', '$2y$10$ZUsSyody3TSb5xC3APIeg.ztM2LlyQJL7Kwe7jZ1FLuV.FMDfN1rm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:04', '40 DT', NULL, NULL, 'فوق 26', '27096391'),
(2731, 'لغماري', 'منى', NULL, NULL, '3qm5zv4n', '$2y$10$BcGxCZFpp4B24HRrvxnugueyg.sWqkHTYUR2l.azXaAQ3ZD0jKsQi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:04', '40 DT', NULL, NULL, 'فوق 26', '93063114 - 92510029'),
(2732, 'مريزق', 'هدى', NULL, NULL, 'sm4fr21r', '$2y$10$Uy5ZbSC940XMDDFNmbm6DufYOOoFVCaQI1KGQ3sB7tE/1gw.ng8ty', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:05', '40 DT', NULL, NULL, 'فوق 26', '51057304'),
(2733, 'عجرود', 'فتحية', NULL, NULL, 'uhtxnqma', '$2y$10$FsiiljubstbLgxfVBkD0DOqQ/FFdK43xI9JeuW4hEsHpIdx75WBWq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:57', '40 DT', NULL, NULL, 'فوق 26', '52532844'),
(2734, 'النوري', 'مباركة', NULL, NULL, 'cw9q61v1', '$2y$10$7uvAU0cz2zQClXOIx8EtdueHzF2qQ8Xf5BZ99aXVJIz6oTEO5XQcS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:34', '40 DT', NULL, NULL, 'فوق 26', '55919261'),
(2735, 'سعيد', 'هشام', NULL, NULL, 'sxcj0pmg', '$2y$10$p8357/adu2yYjqO82aP9wOx1GUCsjTo49/KW9XZs6lkuPlEnnNAai', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:55', '40 DT', NULL, NULL, 'فوق 26', '54058555'),
(2736, 'هميلة', 'ليلى', NULL, NULL, '1m2laucs', '$2y$10$XmLHiCsm4DLf29YwTSk.xOsDLhY2sMipbXNpVqQHX5kVUGntNqE96', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '52952635'),
(2737, 'قعيدة محجوب', 'نجوى', NULL, NULL, 'selz4y2u', '$2y$10$qe.Jj.YfpxpYkKp0o3zale2gxSyVpt7Ty10P1WxgmVtoXls3ATQ4S', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:01', '40 DT', NULL, NULL, 'فوق 26', '..'),
(2738, 'بن حمودة', 'وفاء', NULL, NULL, 'o3t7jtit', '$2y$10$iY7iX5HPx4eDfINI0ix/sOG4PWyWCN2fqH1s1kpByLuSkAQUyqtr2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:39', '40 DT', NULL, NULL, 'فوق 26', '92764413'),
(2739, 'بوقديدة', 'حلمي', NULL, NULL, 'aboj9k1q', '$2y$10$kdzijr.bzeE8Ce2qPLe/Yue8Y7qqaJnvUzGPXa8rKGErE1kXuVzoO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:45', '40 DT', NULL, NULL, '13- 25', '92530733'),
(2740, 'الشطي', 'نجاة', NULL, NULL, 'pe0pg1i3', '$2y$10$o/fVY0Kuxvacyggg0JW/luqjLZeCQjmXD9/8ZcY2eQZ60deceF76i', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:25', '40 DT', NULL, NULL, 'فوق 26', '20872187'),
(2741, 'بوهلال', 'علي', NULL, NULL, 'g50sf8t8', '$2y$10$Zk3ytwncgfgfSKud2n7iNuSNQsLfW89HKMH9zVTx8X5wZA/ota.hO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:47', '40 DT', NULL, NULL, 'فوق 26', '53033015'),
(2742, 'عبد الاوي', 'اميرة', NULL, NULL, '53zfggo9', '$2y$10$WdvK6blGkShoEL4H5QrV..p2kiJJ7OW3jDXPt0wM9tbJZv5hhMM4u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:56', '40 DT', NULL, NULL, 'فوق 26', '98902113'),
(2743, 'يونس', 'سعاد', NULL, NULL, 'sx42urf0', '$2y$10$20PFSjbsLWHUwHqE0qjVtelpq8h2xs5YLfZ4lDvEZWKW4RyxMbn4.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:15:09', '40 DT', NULL, NULL, 'فوق 26', '53849923'),
(2744, 'المخنيني', 'نسرين', NULL, NULL, 'jfo25q1b', '$2y$10$fG2OaNMX3I60sZws0UI/uu0D56X8Jd8JV0kjkP8mhHDdXlbRrWfKa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:33', '40 DT', NULL, NULL, 'فوق 26', '94367286'),
(2745, 'ابراهم', 'رياض', NULL, NULL, 'pcz4ra08', '$2y$10$9jXP/9np5oqdpOnLpFcV4exOz9niBZSCzhzN5l/OEi27s/Mpcg2Yu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:13', '40 DT', NULL, NULL, 'فوق 26', '22638517'),
(2746, 'الفني', 'ايمان', NULL, NULL, '66ixblds', '$2y$10$92xFpDik4Mn247CURTJeTuqD0KLke.LMhGkrRHNBmhRMVWDEV/cou', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:29', '40 DT', NULL, NULL, 'فوق 26', '73259007'),
(2747, 'الصباغ', 'شيماء', NULL, NULL, 'aq20n63u', '$2y$10$29G1MdN8IUAnfumD5IvEpubFHLTMDbl3yJRfES65y0vEIGUd9d6VO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:25', '40 DT', NULL, NULL, '13- 25', '51856317'),
(2748, 'التليلي', 'حنان', NULL, NULL, 'hkqrbnso', '$2y$10$aUKufVq.pTZ17aCCG9oRYeUBEZzqEE8qSg8cPOC9mb3VgDGSV5HsO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:19', '40 DT', NULL, NULL, 'فوق 26', '52191850'),
(2749, 'الشاهد', 'نبيل', NULL, NULL, 'trywefh8', '$2y$10$RN17.vE.fhCGqoyWeI4lQedWAcy0ILEG6YAZWJ2HdIKbaz2qrMCga', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:24', '40 DT', NULL, NULL, 'فوق 26', '98981810'),
(2750, 'ابن الحاج علي', 'ندى', NULL, NULL, 'mejuul0a', '$2y$10$AmucbggWCK5Z5wzzzZR46O7AZLiiX.VJqBucfbGGxl6PsMlRvgrmS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:14', '40 DT', NULL, NULL, '13- 25', '92845516'),
(2751, 'حواس', 'مرام', NULL, NULL, '40npaf4x', '$2y$10$Y4/QPLGbrenQHj9OfFuOf.V7GYtoYZua/QiKxjGcXUOzy7js0kjwG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:52', '40 DT', NULL, NULL, '13- 25', '24400875'),
(2752, 'رويس', 'فوزية', NULL, NULL, 'nv2a8td0', '$2y$10$dT0VOEop5Mdwhct9fSmB7.rTK8XEhlwsr1pb637NuwQp.z.YpLN0i', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:53', '40 DT', NULL, NULL, 'فوق 26', '55718428'),
(2753, 'ابن حمودة', 'اسلام', NULL, NULL, '7gln3gpt', '$2y$10$9t5UdZ7x0hpVivFYsiO04uBVmnSjW9Bki01iI5JFOyDqhEAY6JNyO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:14', '40 DT', NULL, NULL, '13- 25', '54166957'),
(2754, 'رمضان', 'اماني', NULL, NULL, '6s3o21c0', '$2y$10$n1IBYnNgmwyV40LkEHtmTeX3GjVEXG.UcpM.8gVUPApqk6r0sErFK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:53', '40 DT', NULL, NULL, 'فوق 26', '52854455'),
(2755, 'البحيري', 'يسرى', NULL, NULL, 'pszg6nej', '$2y$10$hUwr.3BOlfZHz.3GEem9Zulf6WLa/JxrUcPEj/unQUJurnMzEIkcy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:17', '40 DT', NULL, NULL, '13- 25', '55994551'),
(2756, 'رمضان', 'هاجر', NULL, NULL, 'o3l5ctgn', '$2y$10$ywfiajWNZXrbII//zzAQtOmwWc29yBQDjV9CGCodJn5/L2xs7x2pS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:53', '40 DT', NULL, NULL, '13- 25', '24692214'),
(2757, 'بوهلال', 'سلوى', NULL, NULL, 's8lxtbc5', '$2y$10$Cyo6I95uGa1f.bKKMJucE.vaUtRnWIz2dKVglV7pnIU9wnA6Ig2Nq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:47', '40 DT', NULL, NULL, 'فوق 26', '95116353'),
(2758, 'القايد براهم', 'عبير', NULL, NULL, '86mdw0ru', '$2y$10$SlK.UXa.RoCqIMmlERZ5LOEk5e9Jhk4omon3TrHs7yD1gOGZNIdfK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:30', '40 DT', NULL, NULL, '13- 25', '94858301'),
(2759, 'القايد براهم', 'زينب', NULL, NULL, '4he5pow0', '$2y$10$gBix7gfcW7PkGjQLxj5KMeS943Q9t/QLBv0ORHxvlV85eqziphANy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:30', '40 DT', NULL, NULL, '13- 25', '26320866'),
(2760, 'بورورو', 'ايمان', NULL, NULL, '6j42gurv', '$2y$10$g9rL6NGqdwIFEv0Tixp4fOfrassbLainbXOh4rdSdIRLtg.PCauqG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:43', '40 DT', NULL, NULL, 'فوق 26', '23261529'),
(2761, 'بن الأمين', 'ريم', NULL, NULL, 'kqdts175', '$2y$10$1hyaSsFvFjTiIKskUzcYVOkAds91N6UEHJ23nnQhXi0UhAwufwUM2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:37', '40 DT', NULL, NULL, 'فوق 26', '21313636'),
(2762, 'الفرجي', 'أحمد', NULL, NULL, 'sg5camzp', '$2y$10$m6nRp85dRRjCUEr4EmlYd.Cx.IaXbbv8eDj61JklLW19RdmDlpcHa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:03', '2026-02-28 21:14:29', '40 DT', NULL, NULL, '13- 25', '22922442'),
(2763, 'بوهلال', 'مروى', NULL, NULL, 'jpntq8tc', '$2y$10$byfLTe/x3UWSxBXz2P0Ake1HfYcp3oQsKBYGe/cm1MVFHUdM8Nbny', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:48', '40 DT', NULL, NULL, 'فوق 26', '23612987'),
(2764, 'بن سعد', 'سلوى', NULL, NULL, 'rzrvrm4m', '$2y$10$LsUCmCXWCeBTvGiDaQnbUOcRukx6QvN1wtoTOavZ0I7eYF2m6glFC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:40', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '20740885'),
(2765, 'الدهمول', 'محمد الحبيب', NULL, NULL, 'uhsz26g1', '$2y$10$Ci/6n7HzkWi.PNy5EhbgWudQAllqia/QVGtcuLpwDzUbWlNKKD0q2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:21', '40 DT', '8173498515', 'رشيدة قزقز', '6 - 8', '96689354'),
(2766, 'هميلة', 'فاطمة', NULL, NULL, '58ek6r69', '$2y$10$kPPN7SgwyDQIoaUfQc2aoe5ooKu1Kpkh1uCqad70goe6dvKPWwNtu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '94653857'),
(2767, 'كرموص', 'ايمان', NULL, NULL, 'xdqt2tqx', '$2y$10$1WcSfX844p.QrOJw/QyJXuk4TuqHXJYeHJ1QA5QKh8ni9DtTOotCi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:03', '40 DT', NULL, NULL, 'فوق 26', '23632423'),
(2768, 'ابن سالم', 'أيوب', NULL, NULL, 'tgyi4vhc', '$2y$10$cdIcWcLq/4yWnzN02z.0HO/PbyIFo40w3PGxGjY5Z0a5HhwiDbE9q', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:15', '40 DT', '6476403545', 'محمد ابن سالم', '9 - 12/ 13-17 (للحالات الخاصة)', '21270578'),
(2769, 'العابد', 'الناصر', NULL, NULL, 'xs14iyvq', '$2y$10$AbNRwCegn.uPgS2Kz3YwOuxEo528QDwbAhEnaqEPHCvyGHjTFZ29u', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:26', '40 DT', '9332764969', 'مروان العابد', '9 - 12/ 13-17 (للحالات الخاصة)', '29214643'),
(2770, 'العابد', 'نور بيان', NULL, NULL, 'd7ss2yhs', '$2y$10$uIfJyOx3HuNHdKT.vB.hyurm6g6p7NJz0PbHv8eHzdufdCxqzb9Tm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:26', '20 DT سداسي أول', '1755751732', 'مروان العابد', '9 - 12/ 13-17 (للحالات الخاصة)', '29214643'),
(2771, 'العابد', 'نوران', NULL, NULL, 'jm099nun', '$2y$10$wElVzrFtG96hptVCKPV5OOZf05X0RlFSsSCoZzBZIXYZh68fGLOwe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:26', '20 DT سداسي أول', '6015612321', 'مروان العابد', '6 - 8', '29214643'),
(2772, 'صويعي', 'فاطمة الزهراء', NULL, NULL, 'qvpzaekr', '$2y$10$ootrK36s6ep1MXDIlwdaKO/OgO.hIr8IhXpJxqYp5xvDKKLx7AI2S', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:55', '40 DT', '1850532957', 'فهمي صويعي', '6 - 8', '50934492'),
(2773, 'بدر', 'سناء', NULL, NULL, 'wiir3gvo', '$2y$10$qczref64NqK4hjRJHqc6..F4MsY0vJhyyD2xGYiJKoT.VYPkAunZq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:35', '40 DT', NULL, NULL, 'فوق 26', '23792508'),
(2774, 'الزنطور', 'امل', NULL, NULL, 'zolwicc7', '$2y$10$rz57EY8hSDX9Z7qq7EceOOxFnDgSKV9RNsiGK6xMB0V6hDXdPvOEe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:23', '40 DT', NULL, NULL, 'فوق 26', '99128036'),
(2775, 'بدر', 'سهام', NULL, NULL, 'ejbjcfuk', '$2y$10$ZYbOvF2Iv.KOdJ66ShZJt.fSotxd3FIYRvv5zXdSDYVGz38aex3QG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:35', '40 DT', NULL, NULL, 'فوق 26', '23792508'),
(2776, 'الصباغ', 'سرين', NULL, NULL, 'lqsled2e', '$2y$10$1kNdA6L/ZQPpxVjDnzXNruVjWyzR2//q4Gv/lsgxRgpIntG/fOUSq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:25', '40 DT', NULL, NULL, 'فوق 26', '56739301'),
(2777, 'زقر', 'ليليا', NULL, NULL, 'ni5c6oxz', '$2y$10$RWwWQZ7z1eLNDs0wwKG02.Vz1ySLHs6UW/XduZVWk4KoExgkgxQcK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:54', '40 DT', '1999581844', 'سامية الملاح', '6 - 8', '23757387'),
(2778, 'زقر', 'ادم', NULL, NULL, '8p1vuyt8', '$2y$10$SQtx17mg8z/Alrq/2Tq2keqejA/u.Dy70NOEyYIH9ELhg3ZqLNKx6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:54', '40 DT', '1999581844', 'سامية الملاح', '6 - 8', '23757387'),
(2779, 'مباركي', 'ياسمين', NULL, NULL, 'axvndihk', '$2y$10$db.5KZQ5K0SLuEWqXApS1ew5ZJeqB6RJrddr8GlSQQwy0QV9mNFUu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:04', '40 DT', '7771901593', 'عبير الملاح', '9 - 12/ 13-17 (للحالات الخاصة)', '95720167'),
(2780, 'هميلة', 'يمنى', NULL, NULL, 'v9wjbu7e', '$2y$10$mFHM6fcr7TZoNsO2QbNaZu2Uf7MoaGfQ6JN4aPZEaZOUC6FpF7ISq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:08', '40 DT', NULL, NULL, '13- 25', '28996036'),
(2781, 'الشتيوي', 'جناة', NULL, NULL, 've32y5bx', '$2y$10$fGYSdB4qajRku18KZgsuaOkGxfrQ2JWFsY312bdgLfy3US49dhoJy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:24', '40 DT', NULL, NULL, 'فوق 26', '52192340'),
(2782, 'الشتيوي', 'امنة', NULL, NULL, 'tqr09dbh', '$2y$10$wGY.EmfTEKqx4vQlD/NrkeARdQsVQzipRXhUACpcWg.RUZYwNkVv6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:24', '40 DT', NULL, NULL, 'فوق 26', '58136186'),
(2783, 'الشتيوي', 'عبد الرحمان', NULL, NULL, '87xqupap', '$2y$10$VzGi7.PiTF26/Ah4EYHVVu.AvOlOl3aeukoepSwEplSSOv3J0OY1a', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:24', '40 DT', '4138128720', 'امنة الشتيوي', '9 - 12/ 13-17 (للحالات الخاصة)', '52539244'),
(2784, 'موسى', 'هالة', NULL, NULL, '1abgy3ks', '$2y$10$Yn4PygQIFoDr.gTag3XeuuuZp3h9UKZLg7z5QbgtsLvY3IKqPSCGG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:05', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '98131513'),
(2785, 'القزاح', 'سعاد', NULL, NULL, 'hl0jih18', '$2y$10$4.ZifCGJjay0tbGp5KmN0OAu9lds8o9VZiGxJ3OpnlmRXCBl60y96', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:31', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '50490013'),
(2786, 'الزاوية', 'رحاب', NULL, NULL, 'zwjezxe2', '$2y$10$0qxXNcmJtJ.ZTPrMkkyw3OI4Rh5kfQ26/FOqhx9emFZAWsxlatsy2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:22', '10 DT', NULL, NULL, 'فوق 26', '51058361'),
(2787, 'سعيد', 'ادريس', NULL, NULL, 'wvks9l30', '$2y$10$BT/AZMfUHsi78zgJmCaf5OniJTvCGFc91z8zH8tdfxN.M46SXP1Ae', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:55', '10 DT', '9486911107', 'هشام بن محمد سعيد', '9 - 12/ 13-17 (للحالات الخاصة)', '54058555'),
(2788, 'الرقيق', 'لجين', NULL, NULL, 'xoxwv4vs', '$2y$10$4K42..0Kx8zrmpDrwvq4QeON66eFUVjE7vL0hrbjOnCbarAJ8afOm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:21', '20 DT سداسي أول', '4074336264', 'محمد عدنان الرقيق', '9 - 12/ 13-17 (للحالات الخاصة)', '97122410'),
(2789, 'يوسف', 'نبيلة', NULL, NULL, '7pm6j0ir', '$2y$10$Zc0ELY7wT7IzF3JU9a5vJONeetynMSD2ATU5aqmsEqOYj9BfQAiV2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:08', '40 DT', NULL, NULL, 'فوق 26', '53502522'),
(2790, 'قليم', 'امنة', NULL, NULL, 'oj116wcy', '$2y$10$piurUS8s87UmH1SBlxwV8uosuOPMbOOPuDkXNxQqjvW.prBfljEIy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:02', '40 DT', NULL, NULL, 'فوق 26', '26558590'),
(2791, 'محجوب', 'عقيلة', NULL, NULL, 'dyyln3jp', '$2y$10$w3aM9t8N381H3czHCM5/8eJunkPGPAj1l1I0fusEoxOYspioofMU6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:04', '40 DT', NULL, NULL, 'فوق 26', '54008833'),
(2792, 'ابن خليفة', 'ضياء الدين', NULL, NULL, 'u5uoeg0v', '$2y$10$vDjNZp9tujVdd19.5POIleCuFezKXW2qtWvh5egkFKyy2JtxST80G', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:14', 'معفى', NULL, NULL, 'فوق 26', '22930997'),
(2793, 'بن يوسف', 'وفاء', NULL, NULL, '48tvbyhq', '$2y$10$E/NJD/eGjTjvh7Rc9VpUGuaxBX6.4g.zke48nHS6rEmO4s56HU4si', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:43', 'معفى', NULL, NULL, 'فوق 26', '58169600'),
(2794, 'ابن خليفة', 'مريم', NULL, NULL, '7xscb20j', '$2y$10$8XjH.vjy8MQc/OzSEvqq9ec.37A0OCAFKU2x/5f9eOrLEFbkjBwx6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:15', '10 DT', '5437068652', 'ضياء الدين ابن خليفة', '9 - 12/ 13-17 (للحالات الخاصة)', '22930997'),
(2795, 'ابن خليفة', 'يوسف', NULL, NULL, 'azp4hwrg', '$2y$10$fVCXSTaZyDAf.WxqchtZL.ldeq1aTPel5.sBpzdDAgJA.iXEcM.zq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:15', '20 DT سداسي أول', '9201040888', 'ضياء الدين ابن خليفة', '9 - 12/ 13-17 (للحالات الخاصة)', '22930997'),
(2796, 'ابن خليفة', 'ياسين', NULL, NULL, 'u8dojq9g', '$2y$10$jv370E9DwEkouOoRo.4mc.owIu.BNUBOEwAaEZYHSr8WtPMTGGAvm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:15', '20 DT سداسي أول', '4860834391', 'ضياء الدين ابن خليفة', '9 - 12/ 13-17 (للحالات الخاصة)', '22930997'),
(2797, 'بريري', 'عبد الرحمان', NULL, NULL, 'e2tkm9bw', '$2y$10$M5wCfcyfpdGcYppZo0cSwuFDgGlrbgtY8wk5F2kWlbxAKIXPlSYR2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:36', '10 DT', '.', 'اسامة بريري', '6 - 8', '55257265'),
(2798, 'بريري', 'صفية', NULL, NULL, 'iwhtmciv', '$2y$10$BDQyhzIA3TDJAnNAnNZMOed2NxdiTtjdMvc/lRAiAprG0GAzpeTOC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:36', '20 DT سداسي أول', '.', 'اسامة بريري', '6 - 8', '55257265'),
(2799, 'بريري', 'اسامة', NULL, NULL, 'hi266eea', '$2y$10$AaV6CeFRExvO9M2JmPTCZullVC.mqBbp6Cj3gOLwGoOhEbsyNy3eq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:36', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '55257265'),
(2800, 'بن العربية', 'محمد', NULL, NULL, 'ai5jrtfq', '$2y$10$xhwVnd5ubC4Y5RDZuvBEReSoEvLJqvrpo6HgqOMhn/5qtHV18KfQK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:37', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '98630489'),
(2801, 'القروي بوهلال', 'محمد', NULL, NULL, 'wtrdul1r', '$2y$10$RvfROgeThj04O26d7iYqY.w0pDY0QiNnfAcHdo6Dg3ghi1W/2shi6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:30', '40 DT', '4280298384', 'حافظ القروي بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '41504261'),
(2802, 'هميلة', 'منى', NULL, NULL, 'vkot70db', '$2y$10$IBqeQxjZHmtROkFccMzcF.yn1rKL.NjCk876xEzUk.IMmjvH9WAzC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '53992470'),
(2803, 'المجدوب', 'ليلى', NULL, NULL, 'e5ddr0yd', '$2y$10$lV.MBRXxdTDZPOp7GkE8ZOXNZlTtliMPplUJAsqs/qCZSF4U4vjpe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:32', '40 DT', NULL, NULL, 'فوق 26', '96327056'),
(2804, 'العيوني', 'هداية', NULL, NULL, 'xiek8m0s', '$2y$10$03w.lUx40vKc56HBZ0v7NOh3DkNLgbVSOQcracFexbl7kNG9Ib8V2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:28', '40 DT', '8554142030', 'نيصاف محجوب', '9 - 12/ 13-17 (للحالات الخاصة)', '98624146'),
(2805, 'الدالي', 'سندس', NULL, NULL, 'pfvxzsek', '$2y$10$FlLGrFlABwGrObHRPrDTFeg/vywD0UrTw7WsC2bjvtdqMlkCRmsXO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:21', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '53973994'),
(2806, 'جملي', 'فردوس', NULL, NULL, 'n7gw1onb', '$2y$10$OY2gsje9iD.6TD7I5PxkGuCAWm2i2bvpIjjHXRmC0G/pcd.Rv1o2C', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:50', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '50156092'),
(2807, 'بن سالم', 'اماني', NULL, NULL, 'awskwfys', '$2y$10$CwxVNsnpz88Au8TKsWHxrOz/0GpH5XxvK0RbpmXRIcPH05crxixLa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:40', 'معفى', '6642336900', 'جوهر بن سالم', '9 - 12/ 13-17 (للحالات الخاصة)', '54993807'),
(2808, 'بن سالم', 'انس', NULL, NULL, 's40wlc30', '$2y$10$cv6JnuJu5hGmTZhyvMD6cuM8bL8KGejtzcA0GPP16zfjqkOD8.pRi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:40', '20 DT للعام الكامل', '7995845695', 'جوهر بن سالم', '9 - 12/ 13-17 (للحالات الخاصة)', '54993807'),
(2809, 'بن سالم', 'اسية', NULL, NULL, 'uion635n', '$2y$10$FLt5zhd9nxYRXncIgI6kYuZQaYRT4xM30TJHb/6eTVAvZ6/pZiHQa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:40', '40 DT', '4533253570', 'جوهر بن سالم', '6 - 8', '54993807'),
(2810, 'جرار', 'ريحان', NULL, NULL, 'xub2h080', '$2y$10$xCI2dZ8mrls4Bge2gEm6FuhWFhJnapSlSIB1GThu5o.kfwJjunooK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:50', '10 DT', '4138562973', 'خالد جرار', '9 - 12/ 13-17 (للحالات الخاصة)', '27242872'),
(2811, 'زميط', 'رنيم', NULL, NULL, 'odtxji7o', '$2y$10$DaL7qh0CW7n99FU.0HuKte62P4mthXdJMGaNRGjMgfTEpDPrmos6q', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:54', '40 DT', '9237078412', 'بشير زميط', '6 - 8', '24462533'),
(2812, 'زميط', 'هارون', NULL, NULL, 'khzgenwx', '$2y$10$lCohFZl.uyld1UoYnbC9oO6aKjJztXp2g6i.DTYtq3UI1rtnqyL/O', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:54', '40 DT', '9358724454', 'بشير زميط', '6 - 8', '24462533'),
(2813, 'بوهلال', 'ابراهيم', NULL, NULL, 'vgicsm0g', '$2y$10$tHe2EGMAjmEdGk0Rc4LYBOxXBIWRoFKgDkfgWC3hNU05H/NG/n3CW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:46', '40 DT', '8914200976', 'هالة موسى', '9 - 12/ 13-17 (للحالات الخاصة)', '99037910'),
(2814, 'بوهلال', 'البشير', NULL, NULL, 'xu1li0bh', '$2y$10$R7a36j3Bxss6hhWRSkrG6eYTAIyWathb2nbGARH40lCWA6WVNwb/6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:04', '2026-02-28 21:14:46', '40 DT', NULL, NULL, 'فوق 26', '50523534'),
(2815, 'الغربي', 'آدم', NULL, NULL, 'xc48zhfp', '$2y$10$/1j01QUPKASg8/CapqigCO80mtPVxfGQ0WJrwLu50DxtxkyM6osUy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:28', '20 DT سداسي أول', '2113162073', 'مروان الغربي', '9 - 12/ 13-17 (للحالات الخاصة)', '99855208'),
(2816, 'الغربي', 'عمر', NULL, NULL, 'dqie6vuo', '$2y$10$Az48lptbMwgoM6w4rtmqVu6hOgGgO6oAPF3pDrsuGVZCyJDzVlGoG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:28', '40 DT', '1227750925', 'مروان الغربي', '6 - 8', '99855208'),
(2817, 'العذاري', 'محمد زكرياء', NULL, NULL, 'ezum74g0', '$2y$10$MwE28vwyV64EpCRutDXG/eTdd2dtFaJL0zG6rhUQHtIV4UuSEWoeW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:26', '20 DT سداسي أول', '2848808356', 'نهال بو منجل', '6 - 8', '29835183'),
(2818, 'الجبالي', 'انجود', NULL, NULL, '3ej1lsgw', '$2y$10$EqWpGqCkVJ6VGUimgimElOGCFQ1vSXotBCjWQXRKX9LkGm6ZivKJa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:19', '20 DT سداسي أول', '6185621894', 'ناصر الجبالي', '9 - 12/ 13-17 (للحالات الخاصة)', '22318400'),
(2819, 'القلعي', 'محمد', NULL, NULL, 'fc5ni3gz', '$2y$10$ewZ2rseUh7WvldrvfwAs1uTC9vu/2z0vQFAic7v/86kgumhVzm9DO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:31', '40 DT', '12925960', 'حمدي القلعي', '9 - 12/ 13-17 (للحالات الخاصة)', '21220840'),
(2820, 'بن عبد الجليل', 'روميساء', NULL, NULL, 'utcxmonv', '$2y$10$7FzMFLVEfZIdkBCkmibyfeZsZHz1DfZZi9X3DL/4zm8A.OAFatXyG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:41', '20 DT سداسي أول', '2095136039', 'اسامة بن عبد الجليل', '9 - 12/ 13-17 (للحالات الخاصة)', '98271120'),
(2821, 'بن عبد الجليل', 'محمد ريان', NULL, NULL, 'ofzlwhyv', '$2y$10$GVsTinigLhTvUnvEQZq0t.QVPadqoCluk4ieFjV5R8i2nhTJr4dZG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:41', '20 DT سداسي أول', NULL, NULL, '13- 25', '98271120'),
(2822, 'بن حمودة', 'ابراهيم', NULL, NULL, 'g5qpkmda', '$2y$10$KRpIQLn8QrP1Z8TRMggIKO5VEPdgPvylvXRjpEQKrfdhR.Acx7Gkq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:38', 'معفى', '5596973354', 'احمد بن حمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '55921000'),
(2823, 'بن حمودة', 'اسراء', NULL, NULL, '55tim863', '$2y$10$QUY.rh2k36SyIIZkG1r/0O93im.SIfd87FRogx3njNnlRvyNfF5pa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:39', 'معفى', '8689589089', 'احمد بن حمودة', '6 - 8', '55921000'),
(2824, 'بن حمودة', 'ادم', NULL, NULL, 'kzya029z', '$2y$10$aWxcc7d1jZoPiMuaDuS/ce/LU6WI8Rh232FOMo7EfRJDZMI6EN8ny', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:39', '20 DT للعام الكامل', '3526991031', 'احمد بن حمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '55921000'),
(2825, 'مريزق', 'يحيى', NULL, NULL, 'mo60v89u', '$2y$10$AGLIa7xhE1KCyvywcbxQSehK9WM5miw8N.xU418dpoXWYFZe6ASKW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:15:05', '20 DT سداسي أول', '6103726821', 'محمد شكري مريزق', '9 - 12/ 13-17 (للحالات الخاصة)', '23953234'),
(2826, 'مريزق', 'مالك', NULL, NULL, 'xspg8b03', '$2y$10$CBfY4.qfvNjVpPQUlrHFzu2PbY7Aawz.LI00CEb3w3OZMQEtrs5zW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:15:05', '40 DT', '5582797917', 'محمد شكري مريزق', '6 - 8', '23953234'),
(2827, 'مريزق', 'ياسر', NULL, NULL, 'i52j0igh', '$2y$10$8UtDf/93DBuaxaTVI.SZ7eJAryJx69MRJQ3H4MMjHUjVgPKG6V.C.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:15:05', '40 DT', '9331772236', 'محمد شكري مريزق', '9 - 12/ 13-17 (للحالات الخاصة)', '23953234'),
(2828, 'سعدانة', 'ملكة', NULL, NULL, 'su9vj3gq', '$2y$10$WgEpAKxNj7FwFBYfzT6RW.VBb7BSTnfWXYjZG8bO4exuI3XM1C5jC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:55', '40 DT', '4937710834', 'مروان سعدانة', '9 - 12/ 13-17 (للحالات الخاصة)', '29999147'),
(2829, 'رزق ألله', 'يونس', NULL, NULL, '10aqmj7j', '$2y$10$GpwKxQ3SbzwZ8xhtZE32.OkR2zBnR0qrIhHWmDVcTarSFttzmbRX6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:53', '40 DT', '1767498432', 'مريم العمروني', '6 - 8', '28827052'),
(2830, 'رزق الله', 'شهد', NULL, NULL, 'n47j97ms', '$2y$10$rPrV6Ur9Uqf3jMpVj0GREutGCK91coZpL0rUosDVg36PMen8Zu4NC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:53', '40 DT', '8046043401', 'مريم العمروني', '9 - 12/ 13-17 (للحالات الخاصة)', '28827052'),
(2831, 'حفصة', 'سمية', NULL, NULL, 'twjhpe54', '$2y$10$lFr9oQfFGkEY0QRTwo2M1eH.Bo2I3mU2wakwid8XhShtt3t5N/h2m', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:51', 'معفى', NULL, NULL, 'فوق 26', '29439170'),
(2832, 'الحاج خليفة', 'سهام', NULL, NULL, 'zkqq34bx', '$2y$10$.2rnZ6ssFzvJ0SGMxCVXvuoEZ5AvR7Es91Nd3e6E4x1RlWU.IRUDO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:20', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '96766296'),
(2833, 'هميلة', 'رشيدة', NULL, NULL, 'dhwtu7cx', '$2y$10$XHHFARzHudc6KE6vBbfrjevEA2xYp426phEw6uVhcx8A0KCcvg07C', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:15:06', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '94423123'),
(2834, 'عجرود', 'منيرة', NULL, NULL, 'xs1o3xye', '$2y$10$j2Jzzmhd0bxndvYkOPaQG.VUZFsUN6syjlAAlXs9lL0jyUJSy1WCO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:57', '40 DT', NULL, NULL, 'فوق 26', '98502773'),
(2835, 'بية الشطي', 'اماني', NULL, NULL, 'ytq4ojlt', '$2y$10$3w6.Ca3END5J7YG82xPP7OSLH6bA83eZ8/T0/FGF.ltAtcQ0a2oU2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:49', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '94130305'),
(2836, 'السقا', 'هدى', NULL, NULL, 'u7wc9yw9', '$2y$10$k7AgEWg8UAdCS/ZbW6vLcuWCRVn1cYsHJwPBcl91NDH3vT/EEqg0C', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:23', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '97311103'),
(2837, 'بوهلال', 'زينب', NULL, NULL, '1gipr1bu', '$2y$10$bqrmKfVwfRCZq8QArVSHCeob1KA1GiJWpveV8SZpRhRB06P2AJhUW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:46', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '27042023'),
(2838, 'بن حمودة', 'احمد', NULL, NULL, 'kf4uwhsj', '$2y$10$QV7kRVR6qEZWbvomjrKmVes0grs0uJ.Wibn0mLZojTLnJQSblFWRi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:38', '40 DT', NULL, NULL, 'فوق 26', '58830806'),
(2839, 'بن الفقيه احمد', 'الحبيب', NULL, NULL, '9aqh4kn5', '$2y$10$gw0wxRR3JquEiDzPCOs5DOCEsDmHvJYEi./UKOlO.LfFr7djSiw2.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:37', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '985705445'),
(2840, 'بن عثمان', 'فراس', NULL, NULL, 'sdtf65t5', '$2y$10$dP0IS52J.KX3ecXxKpxCvOAugjxe/Im/lwESlRYU3k.nwz103.l6.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:42', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '22884434'),
(2841, 'المخينيني', 'حاتم', NULL, NULL, 'f7zlg2vq', '$2y$10$vZeV4rE6ffn7X.HirJ/XGu3ycSAj2/.hjiDCRqr3/0EMBnf3Ah4su', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:33', '40 DT', NULL, NULL, 'فوق 26', '29499356'),
(2842, 'الاندلسي', 'ايوب', NULL, NULL, 'w6s0e961', '$2y$10$oDu2qlFZzLactNjlZw4Ux.kJ93tdqyXXX5yiCHO87bZl1nHWs1JLC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:17', '40 DT', NULL, NULL, '13- 25', '20473406'),
(2843, 'العتروس', 'بيرم', NULL, NULL, 'ezx32cs7', '$2y$10$D.KF9gGpMIKG7WgtODVCpeyyms2UMPzKsUWAXdxtD9/2p3i.xa3ne', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:26', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '99269396'),
(2844, 'البكوش', 'خديجة', NULL, NULL, 'k7bdeg8w', '$2y$10$cFmQ2aN.szqjKNxoHl2SyufqWqzZ3R/kOm9tQRfdGorJnAw7ZCgVi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:18', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '27275962'),
(2845, 'قليصة', 'عثمان', NULL, NULL, 'ou6so7g6', '$2y$10$GDRJxQXy2valepBGfNtNFesAOWvQCK2vjIxGKau/qIRF6MpJ3jEnC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:15:02', '40 DT', NULL, NULL, 'فوق 26', '52557458'),
(2846, 'بية الشطي', 'أسيل', NULL, NULL, '5o5ktxb6', '$2y$10$Zb7rU3rSWcoIV58DYDUswuBtIlSTjnp5Dm/4boUaAc.CglaS4yuHu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:48', '20 DT سداسي أول', '7393990506', 'هاجر براهم', '9 - 12/ 13-17 (للحالات الخاصة)', '27330688'),
(2847, 'بية الشطي', 'سليمان', NULL, NULL, 'bdut2o3p', '$2y$10$TerBwbJ.ylmKoJcW69qvNuEnh6/BOjXNDEEAdhavmK4QQKZcWVQoW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:49', '20 DT سداسي أول', '1487365866', 'هاجر براهم', '6 - 8', '27330688'),
(2848, 'بوهلال', 'فاطمة', NULL, NULL, 'l9osxyqs', '$2y$10$op40O8XGQFtNUknU2riDpOJB3dmVbmjqt7dDNWOtJs9KdYddeDpG6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:47', '10 DT', NULL, NULL, 'فوق 26', '26543704'),
(2849, 'بن سيك علي', 'يسر', NULL, NULL, 'nlnigfdj', '$2y$10$Pbg9grKyWktVhOdcAKYERu0chcjNGHwk/QCG4UvbdZPK7K1FTvMTe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:41', '20 DT سداسي أول', '7979602845', 'امحمد بن سيك علي', '9 - 12/ 13-17 (للحالات الخاصة)', '26543704'),
(2850, 'بن سي علي', 'احمد', NULL, NULL, 'mztz59zp', '$2y$10$1o1GUQ8Gixt9eI3I37ePv.Kf4XumliiE4QHLs5AEBU9R67CKIstPS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:40', '20 DT سداسي أول', '1312494468', 'امحمد ابن سيك علي', '9 - 12/ 13-17 (للحالات الخاصة)', '26543704'),
(2851, 'الشطي', 'امل', NULL, NULL, 'gkcqjv6o', '$2y$10$H2e1B2oeYajsJA1v40FVOuVcvjQ7yzRRzcU/rjHMlTSLHE/eCDp1.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:25', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '21943525'),
(2852, 'السوسي', 'نعيمة', NULL, NULL, 'c1nm0d7u', '$2y$10$N/WEO7CwUqd0UnDhswQIDeghQ.gs8SL.H5rNGfsw0uVYrpI01kNri', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:23', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '24114623'),
(2853, 'يوسف', 'حمزة', NULL, NULL, 'ljg7fvaj', '$2y$10$9jQv7RQJNY303MuxhBsqn.SKLKnpIJxLsWBuy2E9Ik34lDIZ4C/l6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:15:08', '20 DT سداسي أول', '8564214670', 'محمد يوسف', '9 - 12/ 13-17 (للحالات الخاصة)', '29003810'),
(2854, 'بريري', 'منتهى', NULL, NULL, 'e8c8z9gf', '$2y$10$lGEWGUl.AwWffW71z4qCKur899oiSlyClakXVm8PbMKitf0qt5mS2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:36', '20 DT سداسي أول', NULL, NULL, '13- 25', '22746406'),
(2855, 'كريفة', 'خولة', NULL, NULL, '0f7crvqh', '$2y$10$LGQHEbuVqmhnDx1NLfnykemXiKKjiytn5VaeWwL5aQLWyFeNvSQM.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:15:03', '20 DT سداسي أول', NULL, NULL, '13- 25', '53981986'),
(2856, 'الرقيق', 'احلام', NULL, NULL, 'dlv1ww0l', '$2y$10$kUAzUTTe61PGSW86/uOX/eylXJuc7PEh7KoIm4e3jK4pWE3uRw/gi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:21', '40 DT', NULL, NULL, 'فوق 26', '54411433'),
(2857, 'القزاح', 'ايوب', NULL, NULL, 'fksijzok', '$2y$10$RSUIv.QN3FI5x3TePsi8jO.FTt2AIwlTni7krma/lBH//ugSs3p0W', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:31', '20 DT سداسي أول', '3926673669', 'سفيان القزاح', '6 - 8', '27190074'),
(2858, 'الفرجي', 'ابراهيم', NULL, NULL, 'loxdddz8', '$2y$10$NHWUSLgAFzNaqq0.zMinJO5YW//ZGbiGPVxTJ3n0YB23YzK0YH2Dm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:29', '40 DT', '4727535678', 'محمد صالح الفرجي', '6 - 8', '56608706'),
(2859, 'زميط', 'محمد يحي', NULL, NULL, 'x5le7eur', '$2y$10$dna/gX6KHgOjxCCZoRAMVupZZSglbbV6wbRGxaU/xnND/DGkhIoYS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:54', '40 DT', '6025311513', 'سامي زميط', '6 - 8', '98476443'),
(2860, 'زميط', 'عمر', NULL, NULL, 'xbwlat26', '$2y$10$VgzHtyDviN6j89gUi21gieJabxrWTrL0GCykIp4EkkgOz3rm1jkAS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:54', '40 DT', '3582259409', 'رمزي زميط', '6 - 8', '22627027'),
(2861, 'زميط', 'محمود', NULL, NULL, '48cbxkiv', '$2y$10$O3rnfADyx877BWhAOYa9neMGlpOREKx0i0VVjg09Umr/hzO56ncWi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:05', '2026-02-28 21:14:54', '20 DT سداسي أول', '1396279028', 'رمزي', '6 - 8', '22627027'),
(2862, 'بن ابراهيم', 'حمزة', NULL, NULL, 'rxow1ssc', '$2y$10$cXO1Mtb1lWwN1XqQ935rQOIFU64IlQsJGScJJtTcME.ejdfXp3vAm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:37', '40 DT', '8202948880', 'نبيل بن ابراهيم', '6 - 8', '21384348'),
(2863, 'بن ابراهيم', 'عمر المختار', NULL, NULL, 'g1sglylm', '$2y$10$xfqk2f2voi0vZOlNV3coSO1Apv4AK0Ssr8c1GntoKAUYUEYh6rJxa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:37', '40 DT', '3502644334', 'نبيل بن ابراهيم', '9 - 12/ 13-17 (للحالات الخاصة)', '21384348'),
(2864, 'الشريف', 'وئام', NULL, NULL, '4jyknd0a', '$2y$10$8Qh0AO5FiTmeKxM/biAIxuoAlDvCB/fnDgwogoV7G0SjM17lK.Mj.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:25', '20 DT للعام الكامل', NULL, NULL, 'فوق 26', '92513894'),
(2865, 'البكوش', 'اسماء', NULL, NULL, 'gpjajbq1', '$2y$10$gqcJG6MX3zCnZQR0yKAGde1j663R1lqCP5F0l5o0EeNHlK.zOBcCy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:18', '20 DT سداسي أول', NULL, NULL, '13- 25', '58498855'),
(2866, 'عبد الجواد', 'وسيم', NULL, NULL, 'yxo35lhj', '$2y$10$DfqCFUMzyEqT6SUD3ve.N.TSUf.04VqwvEvI8JywR8ym9atJP3H9m', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:56', '40 DT', NULL, NULL, 'فوق 26', '23408002');
INSERT INTO `students` (`student_id`, `last_name`, `first_name`, `middle_name`, `name_suffix`, `username`, `password`, `last_login`, `failed_login`, `custom_200000000`, `custom_200000003`, `custom_200000004`, `custom_200000005`, `custom_200000006`, `custom_200000007`, `custom_200000008`, `custom_200000009`, `custom_200000010`, `custom_200000011`, `created_at`, `updated_at`, `custom_200000012`, `custom_200000013`, `custom_200000014`, `custom_200000015`, `custom_200000016`) VALUES
(2867, 'الزرلي', 'ابراهيم', NULL, NULL, 'iwg759g2', '$2y$10$PG.sXAT0zzwl9dvZXsl2SetCA/Cb37TFtyc/8y6g3wvyjLENJ2UVW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:23', '20 DT سداسي أول', '4929095517', 'نضال الزرلي', '6 - 8', '98414335'),
(2868, 'الاكحل', 'احمد', NULL, NULL, '491s4oqb', '$2y$10$A6lTq4sfbeRdp68F1W9xo.1x0RtjWK3JtNDQoE5un/V8jm7UzNuiq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:16', '40 DT', NULL, NULL, 'فوق 26', '96263331'),
(2869, 'كشاط', 'سميرة', NULL, NULL, '3a1uj1xs', '$2y$10$S6JmzyfKqBgr5RvNSpnMgORjxNI7Io5UW6M1Mw7Pkvlm.5gz.jY1O', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:15:03', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '95718586'),
(2870, 'المحمودي', 'قيس', NULL, NULL, 'kml14v0u', '$2y$10$N2JRpPahfBgfG/DLMWrm/.xeNnSNWeI/Yu7tR5L3OZcIAPSbIhjku', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:33', '40 DT', NULL, NULL, 'فوق 26', '51622690'),
(2871, 'الجلاصي', 'سارة', NULL, NULL, 'b5fjflhb', '$2y$10$5bhq0OsIfNeG4lv.hijqkOaEVb8ciAi35ojZgQ6D49EfDk6NDblWC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:19', '40 DT', NULL, NULL, 'فوق 26', '50970124'),
(2872, 'سعدانة', 'زينب', NULL, NULL, 'rtya0bmz', '$2y$10$kw5iy/SB6YF3QreNa21kB.JIDH6CPYXRmvT3nRKC1P971fth6DsMy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:55', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '99772714'),
(2873, 'الزبيدي', 'الزهرة', NULL, NULL, 'uw91s3oi', '$2y$10$voVhOwwraL59PQ6szJ.wme4hoXLrp5ep3Xo4owbBnQcX9G6EKMwn.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:22', '40 DT', NULL, NULL, 'فوق 26', '23670608'),
(2874, 'كريفة', 'معاذ', NULL, NULL, 'nd0jdiwj', '$2y$10$5d4/zr.OdP.m/QYJ9I8BfOD6t9KSuuzVgrGWTqqN5s1z6ccuFHjHm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:15:03', '20 DT سداسي أول', '2392295034', 'محمد كمال كريفة', '9 - 12/ 13-17 (للحالات الخاصة)', '98184480'),
(2875, 'كريفة', 'عمر', NULL, NULL, 'nt31hz79', '$2y$10$y4tiU8DvHbgUodmZh4tqFOuehYci.LVEUDctDAhAj8rduW/AlaBfu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:15:03', '20 DT سداسي أول', '7662774270', 'محمد كمال كريفة', '9 - 12/ 13-17 (للحالات الخاصة)', '98184480'),
(2876, 'فحيمة', 'منى', NULL, NULL, 'jv30w36e', '$2y$10$BCe42PEt1e7F4GrwvShNhe7I.wLgP6ciKFsMcsFYzgZa.dEO7zBfG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:59', '10 DT', NULL, NULL, 'فوق 26', '98184480'),
(2877, 'كريفة', 'احمد رامي', NULL, NULL, 'p7s9aj4m', '$2y$10$YA39ygGTUUdcwqWE0tfPNugp4dv7DM0pfeGWoXnw2BbFmKT7aQfp.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:15:03', 'معفى', NULL, NULL, '13- 25', '98184481'),
(2878, 'بن عبد الكريم', 'محمد أحمد', NULL, NULL, 'l4ta2jcs', '$2y$10$CZu.CXKJHFwrzYFwNMqr1eDQbudvRcc4k3Su6JD7Kc8kcKpSNTobG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:41', '40 DT', '9693472809', 'سامي بن عبد الكريم', '9 - 12/ 13-17 (للحالات الخاصة)', '23777480'),
(2879, 'تريعة', 'انس', NULL, NULL, 'b6ftzrmg', '$2y$10$BwcChqVQ0TK.FqovBSZGAuLHpsdqOftUcAddPvSXS9ORWfudHMwOi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:49', '20 DT سداسي أول', '6438505229', 'لطفي تريعة', '9 - 12/ 13-17 (للحالات الخاصة)', '95528681'),
(2880, 'هميلة', 'مها خلود', NULL, NULL, '1le7corb', '$2y$10$JYF.V/e92cPg7MRhoxpvAuovO.u9ef8YluA2YGJaM6dSpg7g/YTcS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '29050051'),
(2881, 'بن الحاج الصغير', 'آية', NULL, NULL, '8ty6zhwy', '$2y$10$5Nm8.e4GLXuznaPY0i7y3.vaKyZo/VyY161AgMKEST2CoAPNWqBA2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:37', '40 DT', '8527556754', 'وسام بن الحاج الصغير', '9 - 12/ 13-17 (للحالات الخاصة)', '.'),
(2882, 'الغربي', 'زينب', NULL, NULL, 'ya4z0ke1', '$2y$10$59MAZMby2ueswoRUed6BoOikugz8AxJA4dVEG/ips3bF1tzmTB8xW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:28', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '28071351'),
(2883, 'الغربي', 'اسراء', NULL, NULL, 'ztyh2zrf', '$2y$10$7dqbueWQ9UJFdFR6IykLge/EYA8YQ0ySoTWRF5f.2yqu7ueNbuxgm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:28', '20 DT سداسي أول', '9182890875', 'محمد أيمن الغربي', '6 - 8', '28071351'),
(2884, 'بن عبد الجليل', 'ابراهيم', NULL, NULL, '3ldy19o8', '$2y$10$YNm0KvvrFOQxa5DFQ9hFO.novmtIofP2JSUywy//qK4mbpeaSpk4i', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:41', '40 DT', '7327295124', 'فتحي بن عبد الجليل', '9 - 12/ 13-17 (للحالات الخاصة)', '28700840'),
(2885, 'بوهلال', 'عمر', NULL, NULL, 'ph7ceky6', '$2y$10$6h/GtDuuiVWEkIKTNDWcde9BJcN9bmino0l/jlMiGWabzqqEHiU2i', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:47', '40 DT', '9059468681', 'مجدي بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '22820901'),
(2886, 'الباش', 'هدى', NULL, NULL, 't68js3xb', '$2y$10$MpXXFjWNtpZR08u4FL.Yz.XgKwTl7hn4/d7PvcGjxOSpXyN5cvCMi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:17', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '56441036'),
(2887, 'مريزق', 'صبرين', NULL, NULL, '39mdt611', '$2y$10$SXGNwDvXvMAtH9CCbYEP.ujnz8SoelV4LayPNL6rlmKQ2Yy8goCZ2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:15:04', '40 DT', NULL, NULL, 'فوق 26', '92142103'),
(2888, 'عميمي', 'أنيس', NULL, NULL, '6me0avn0', '$2y$10$8qdJ8u9bGGMCXer1zMlOE.wJSucnMMWnsLJmerqzQqiZ7sRGpM0/G', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:58', '40 DT', NULL, NULL, 'فوق 26', '54466210'),
(2889, 'العيوني', 'وفاء', NULL, NULL, '7zh41rdw', '$2y$10$OCc5KbuasBS7M5aBNJoT2.xCkyjbqhch33f5ugwGn/VgrIEXgEePi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:28', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '22679626'),
(2890, 'بوهلال', 'روضة', NULL, NULL, '46uvtz01', '$2y$10$WSbOEgONcTs/FtDQKW7VzOrIpgaQBWXl4pHiip9k4eoNcsMgwAihC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:46', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '22210203'),
(2891, 'ابراهم', 'يوسف', NULL, NULL, '3ydg8azo', '$2y$10$EgRS1Oa1rEi7YtYINqMV9OFBnuIHCAvK84lAI1fSDDzP1IzNzVIJ6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:14', '20 DT سداسي أول', '6314768506', 'محمد ابراهم', '6 - 8', '22297037'),
(2892, 'حواس', 'سارة', NULL, NULL, '0ok45nmv', '$2y$10$nVKyu63xE1HkNMkS4e8eCeVzDtnBxfCbDc1NSvisAuobRd5MPshQi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:52', '20 DT سداسي أول', NULL, NULL, '13- 25', '99795128'),
(2893, 'الصيد', 'امنة', NULL, NULL, '1lrmk0wr', '$2y$10$xkpbZLpJ.EBZHoGE/xO7p.IVpY9OJ1Q64pvqESXOFQwzlE66HYMhG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:26', '20 DT سداسي أول', '2471038422', 'رياض الصيد', '6 - 8', '20890450'),
(2894, 'الصيد', 'أبو قاسم', NULL, NULL, '60pf5knz', '$2y$10$XiQr1OQNOjMXvDqDje2yBuslgzIuP5XuNwBtMZGlHranyx8Kfembu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:26', '20 DT سداسي أول', '8259849787', 'رياض الصيد', '6 - 8', '20890450'),
(2895, 'بن حمودة', 'يوسف', NULL, NULL, 'gcqmawp7', '$2y$10$kimgyVxqz13JlqoLKcQZnu4JVrM2D/csdM7QcmoblW0Com.CrSzhq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:39', '20 DT سداسي أول', '7417228369', 'زهير بن حمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '52852247'),
(2896, 'بريري', 'بية', NULL, NULL, 'y8i3k0f5', '$2y$10$UmSJIZdfhEHqTGBeLOR6T.9g2LVQWI42QZ4MouUFz4rrjLY44S7NO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:36', '40 DT', '9991719719', 'رمزي بريري', '6 - 8', '56481480'),
(2897, 'بريري', 'محمد يحي', NULL, NULL, 'wrp8e56q', '$2y$10$.yUvzg8Jomfhs60HFs/rGuZJQEjer30DFlHz83aqOaj7pMmGqz/WO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:36', '40 DT', '5030984156', 'رمزي بريري', '9 - 12/ 13-17 (للحالات الخاصة)', '56481480'),
(2898, 'بوهلال', 'آية', NULL, NULL, 'lpqmbudi', '$2y$10$XIYyEYzANtuU9CKUl99fgOlt0zQIPoiNcZ6vbNmzmTulSj3lbFvFm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:45', '20 DT سداسي أول', NULL, NULL, '13- 25', '24505604'),
(2899, 'الصكلي', 'عائشة', NULL, NULL, '7slipxzx', '$2y$10$PfTRbUMDaTsj4q.Pc3FEWuYfD3/NJbs1Lz7SiMxG/LsP54qGvnSV.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:25', '20 DT سداسي أول', '4721030315', 'وليد الصكلي', '6 - 8', '58303109'),
(2900, 'زنينة', 'سناء', NULL, NULL, '3xzfur6u', '$2y$10$a2SULmfFQYCk7SBAwwcqkOM.ZnvjfWZetYHA.8Om1Sl/uY9rW74mS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:54', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '58303103'),
(2901, 'بن عبد الله', 'احمد', NULL, NULL, '2i1d71ox', '$2y$10$ZYdRfHdwqTXkpAj2.EuBIuHj495oUNwIb1MLE71jclXttIo8SzwyS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:42', '40 DT', NULL, NULL, '13- 25', '55047472'),
(2902, 'ابراهيم', 'ريان', NULL, NULL, 'cejs70zj', '$2y$10$bRh3UwsJBI8KqGF.fZiy2.WLMUUOm79I9qiWFoWvF0dEGVPdfxcr2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:14', '20 DT سداسي أول', NULL, NULL, '13- 25', '22228763'),
(2903, 'الغماري', 'محمد ابراهيم', NULL, NULL, 'o81yw4ci', '$2y$10$3U4NM9hPPlqEZF30CjnqCug.a9AWyqIo4iJh5yt3rfLndvwE8cOFm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:29', '40 DT', '7356260536', 'مروان الغماري', '9 - 12/ 13-17 (للحالات الخاصة)', '25183434'),
(2904, 'هميلة', 'صابر', NULL, NULL, 'ikvpsig4', '$2y$10$R8K.o4XnV8wq9Wi9QuOiOe7boS58TPsm7ZLwQT6l42zjSsWSZseYa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:15:07', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '46307875'),
(2905, 'خليفة', 'سكينة', NULL, NULL, '2faeiogv', '$2y$10$m6pcAACI955sbXVt.w5F/.gLt3rSKjBMXUdeBGOZgzLc7XAELnEsK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:06', '2026-02-28 21:14:52', '40 DT', NULL, NULL, 'فوق 26', '08492064'),
(2906, 'البكوش', 'لطيفة', NULL, NULL, 'rp0a7wc5', '$2y$10$vGs1xS63wskipnwrbx1smuqnoYdo7raN7BGuDuV0U1wCKBnJIyDWy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:18', '40 DT', NULL, NULL, 'فوق 26', '52509025'),
(2907, 'قرع', 'رماح', NULL, NULL, 'du1i8kei', '$2y$10$jAkNo9MCEumT1AWFF8N9SuTM2gPFkx2EvYkdcv5yLntIb1dgOpM72', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:59', '40 DT', NULL, NULL, 'فوق 26', '23403918'),
(2908, 'جرار', 'احمد', NULL, NULL, 'lib7i839', '$2y$10$cXVL1CXTTkr.WMV6g.x/kuw8h98LbGiFd5JRjtXJPQZaw2JNcUss6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:50', '40 DT', NULL, NULL, '13- 25', '25767236'),
(2909, 'البكوش', 'شيماء', NULL, NULL, '07z3kbgt', '$2y$10$VJGtSKZFTUoFnFAvqYlNaO9jkQ3Lgt8hDCcHWpYh26pKZGno922wu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:18', '20 DT سداسي أول', NULL, NULL, '13- 25', '97255245'),
(2910, 'البكوش', 'نور الهدى', NULL, NULL, 'qaqhn5wj', '$2y$10$TPxDPRgGECDXVUDpRE6pTuO2Te7wYUUkWQ6Uc63jRnI4cXGPnpupa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:18', '20 DT سداسي أول', NULL, NULL, '13- 25', '50702156'),
(2911, 'نوير محجوب', 'نادية', NULL, NULL, '3vku6945', '$2y$10$UFaMsoCzxEsBYbhNwPhr9uIQH.l5CdHIfLWYxuzXKMQHcZpLpeJVS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:15:06', '40 DT', NULL, NULL, 'فوق 26', '24011877'),
(2912, 'النفاتي', 'امة الله', NULL, NULL, '86r2p0ro', '$2y$10$xMVxln/GATHCVi3xCXJFU.3ac60wJJgzteTaW9H3ERWZcP3L6ucyu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:34', '20 DT سداسي أول', NULL, NULL, '13- 25', '50243388'),
(2913, 'البزيوش', 'اكرام', NULL, NULL, 'vfs7qvc2', '$2y$10$x2.8Yq1bkMXsDhtvD8dQIu6tdPTQVSySXKCsJOMeZYzmC6ix7kOg2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:17', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '55657166'),
(2914, 'القارص', 'هدى', NULL, NULL, 'lqc5cffy', '$2y$10$fyG6iNQlF2WCTF75b47D0.mk.7XqDuMhOh.l2Q.aHyUGvanYORqAK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:30', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '28785906'),
(2915, 'هميلة', 'ألفة', NULL, NULL, '4kf1tlfi', '$2y$10$rPZKwS.x8EvE4/zxyK9JkeIkGZIZliWBIhTPsRs1H7SnLAe6WJJcK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:15:06', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '29006228'),
(2916, 'بوصويفة', 'آية', NULL, NULL, 'l07oz8t3', '$2y$10$1nIV8Hb/BAbfpj4glBqaOueArOa3K7kEKbwTHRYh7vzxMHhtazAEO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:44', '20 DT سداسي أول', '7332453100', 'محمد صابر بوصويفة', '9 - 12/ 13-17 (للحالات الخاصة)', '29006228'),
(2917, 'فلفول', 'وفاء', NULL, NULL, 'qdowd74g', '$2y$10$KtfHpla6Ov365ivy28CCGeADyhnfHvT1P8BjFIeAjXaJKG3gVu4si', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:59', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '50519498'),
(2918, 'البكوش', 'نجود', NULL, NULL, 'znfzcmzg', '$2y$10$vC/bINMSQUAj.jvOHmlaoOlyQPQhH/N6ofgokoDKWDg4ld34spWfa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:18', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '23870135'),
(2919, 'بن عزيزة', 'يحيى', NULL, NULL, 'ezj1t359', '$2y$10$XitOjSH8brb9DpcQm1ar5.9Jel1pTXi.uwNXfXuJ1w61KaKlrXv6q', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:43', '20 DT سداسي أول', '9504332307', 'كمال بن عزيزة', '9 - 12/ 13-17 (للحالات الخاصة)', '28505390'),
(2920, 'بن عزيزة', 'نوران', NULL, NULL, 'k01yjg1u', '$2y$10$XMnZFWbswoxZ5BmVzoaLTe/x5IkFCQt5Ao/0glNbV139.ieDLE5Hi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:43', '20 DT سداسي أول', '2585371110', 'كمال بن عزيزة', '9 - 12/ 13-17 (للحالات الخاصة)', 'كمال بن عزيزة'),
(2921, 'ذكار', 'امينة', NULL, NULL, 'fryxwjc1', '$2y$10$OyBtr2qY6fku19u3HZ5uY.4qho36JRNBnsrj9rDtlo50mWxG4wSje', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:52', '40 DT', NULL, NULL, 'فوق 26', '96541682'),
(2922, 'القزاح', 'امال', NULL, NULL, 'lziho91z', '$2y$10$Ad/ey.wBGk6Df2VGPeRTLef41fglFTEPLMdQWo0uKB/DabxwsfEZK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:30', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '53542784'),
(2923, 'بن صالح', 'آمنة', NULL, NULL, 'xxxufxy2', '$2y$10$nPlZ64sr50Z6B6Dj.Gng8e0mKgMcTBU.E2RG0EKrH8TSjFiVNI4ym', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:41', '40 DT', NULL, NULL, 'فوق 26', '99092356'),
(2924, 'عمار', 'بثينة', NULL, NULL, 'f7dlcjsf', '$2y$10$r2Jj6HBfjAh5V92zwoOThOwY.DjtuXloX6syxlHnGACHnPJqT7KQC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:58', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '94858833'),
(2925, 'شعرانة', 'اميرة', NULL, NULL, 'o1yun77j', '$2y$10$kXSKjvzvZqZrXF5LKjESO.ATveLdbr73RaOt57MyjAV9UfrPygXUy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:55', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '54536138'),
(2926, 'بريري', 'رانية', NULL, NULL, 'fqyoej8q', '$2y$10$oM11wNBgCotzaBxjl7fihuyzJf1P/WYMBXXzJoKqCO54v9Q6e84ue', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:36', '20 DT سداسي أول', NULL, NULL, '13- 25', '99150700'),
(2927, 'بو ثعلب', 'سنية', NULL, NULL, 'w6troc70', '$2y$10$5E/197ACPtHjmM6jxZGXLuFRWn7Bqm3pYI8uEITV33418hbuPZtEe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:43', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '52155659'),
(2928, 'بوهلال', 'محبوبة', NULL, NULL, 'giu6qf2t', '$2y$10$sCu.9u73B55NwtvHuGHXXuG.PDqhto3Xi/xR4SKd.3puw04TP4Gj6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:47', '40 DT', NULL, NULL, 'فوق 26', '93197645'),
(2929, 'علية الشيخ', 'سميرة', NULL, NULL, 'n9z6iktk', '$2y$10$VWn21FNDVSwCQTwvMEn.JutDhqVE69mOsmyAO1w5Dqz1aJjVuSvXu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:58', '40 DT', NULL, NULL, 'فوق 26', '96258594'),
(2930, 'القروي بوهلال', 'عبد الرحمان', NULL, NULL, 'jjvcvywh', '$2y$10$Qo485vBLPQsAY.XWfrQMi.dVvXsS5D/DVRSjL0K4KwuzORwVapDI2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:30', '40 DT', NULL, NULL, '13- 25', '41504261'),
(2931, 'الشتيوي', 'اسماء', NULL, NULL, 'dxr22r3c', '$2y$10$aI9BwE/igWYmXKJpZNF9JeSIDI5QZbT.SyWDzG5jToWUC8IUjqMEW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:24', '20 DT سداسي أول', NULL, NULL, '13- 25', '50596979'),
(2932, 'بن حسن', 'مريم', NULL, NULL, 'mrs76xw9', '$2y$10$pM3x1OghtUGyajyjX0VX8ehLxZ5PW8aLjbS/hXKtbkUNuAv/WHW.m', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:38', '40 DT', NULL, NULL, '13- 25', '29379778'),
(2933, 'ابراهم', 'ياسين', NULL, NULL, 'j7azjaki', '$2y$10$R9ZTrnIZ0Q0i0z4gXkjEDOzLYGJexoWKVIJWB5t8/ol72R8ztP5VG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:14', '20 DT سداسي أول', NULL, NULL, '13- 25', '20211002'),
(2934, 'الصباغ', 'سعاد', NULL, NULL, 'c3xuqyw2', '$2y$10$wzbsGA5.W9Rem3GcEsAXY.nQDuCKcCh7TSikF2BcmnISq6.nPgbES', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:25', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '50596979'),
(2935, 'براهم', 'ابراهيم', NULL, NULL, 'a6mobpad', '$2y$10$buzIWM7V6BtiQUEzAzLVOeIOTSNqJqivau.mSaMue3EAgBjRhOnnK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:35', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '23570722'),
(2936, 'بوهلال', 'ايمان', NULL, NULL, '3g54r2xv', '$2y$10$dBktUDnVwMXMg.77uzWXQOOKDbhUmOlhZoyRYHWUePz515A76EVWG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:46', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '99309320'),
(2937, 'عليه بن خليفة', 'زمردة', NULL, NULL, 'h2lug181', '$2y$10$aURo/MIDP0V5PSVWn8QtQezQ.mf2f.72DNvZYiyqV3ARBIgVmwLvG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:58', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '52998841'),
(2938, 'يوسف', 'حليمة', NULL, NULL, 'th9y6byb', '$2y$10$09/umYIkCEMjGeaVCfJSmeEYSWs2ew9vQRrl9OMcz/l8vrBOdkdQ6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:15:08', '40 DT', NULL, NULL, 'فوق 26', '95472002'),
(2939, 'بوهلال', 'امة الله', NULL, NULL, 'kskk4ss4', '$2y$10$1uvNbSoKoeT3sVMszEW1XO1BH9OFDokTBqRzHuJJLIJNi/JsXMjIK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:46', '20 DT سداسي أول', NULL, NULL, '13- 25', '24098970'),
(2940, 'يوسف', 'دليلة', NULL, NULL, 'i5ouyuoe', '$2y$10$KxhOk37DKkW0CGEJAge9CeLHNyhGV30DNuiZmosNv5uLIeDdiptoW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:15:08', '40 DT', NULL, NULL, 'فوق 26', '27273196'),
(2941, 'العشاش', 'سميرة', NULL, NULL, 'ga94dhci', '$2y$10$NRkrQDFD4aojBSRgg6mPeOMUNqThCVlBkMYmG50JsJTBxuGfJ2v2y', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:27', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '96766109'),
(2942, 'الزمرلي', 'لطيفة', NULL, NULL, 'pu0g69e1', '$2y$10$6HlU4dFaIp51KRt4bXUAneyWN7DGLQnRuHyy4RkZA/HBgWCx/daau', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:23', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '73262116'),
(2943, 'الصغير', 'فاطمة', NULL, NULL, 'fuiw06nm', '$2y$10$jC0Sj32gN9Scj9FjH8OnfeJIOPjMFg2TVFWJatcsezkD0NVt3GfEm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:25', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '55614819'),
(2944, 'بن الحاج خليفة', 'ريم', NULL, NULL, 'fzd27u7r', '$2y$10$wJHYDYyNH.ZzHREBEoGpPe/umFhOu7ZAxjKEImpraPUB1HT.Pf4Be', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:37', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '96008585'),
(2945, 'مريزق', 'دليلة', NULL, NULL, 'zz6fnn5b', '$2y$10$GOkXpO8PnE/JjPiEogwZ2.rp5KPBvHpD6pgMc4kQVg8cQkVu2TApy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:15:04', '40 DT', NULL, NULL, 'فوق 26', '22905104'),
(2946, 'بوعزة', 'لبنى', NULL, NULL, 'ua49lhpt', '$2y$10$IEbXXQHTI0l.QQgWQiC7Te6qBkahBthhzK7TVaJxzLcOE8rMzlaGq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:44', 'معفى', NULL, NULL, 'فوق 26', '28990534'),
(2947, 'مصباح', 'ميارى', NULL, NULL, 'qisvhsy1', '$2y$10$NTQsJyue/zLeMRnXtEfLt.YgpbO4RoLyEz./zdTPjtTwJFG6FQ8E2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:15:05', '20 DT سداسي أول', NULL, NULL, '13- 25', '52420888'),
(2948, 'كريفة', 'سعيدة', NULL, NULL, 'l2dlrura', '$2y$10$LDTwMD//ghX9ErRZfnNPVuBncro5XFFn7rplv/lii82NAqsePp5em', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:15:03', '40 DT', NULL, NULL, 'فوق 26', '27095223'),
(2949, 'ابن عبد الجليل', 'فوزية', NULL, NULL, 'an5ss381', '$2y$10$aVha3/eFAUNKRbQsCfBiOeXUc1KdhNzC1xbWa/ucsu9whQ/QnWkW6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:07', '2026-02-28 21:14:15', '40 DT', NULL, NULL, 'فوق 26', '51483010'),
(2950, 'التليلي', 'سنية', NULL, NULL, 'mrh88ic4', '$2y$10$GdrLUKlmJqE/m3ma8LJ6UOKX6/dVHXZobCTgSfWZdyD8SHPZOnnZm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:19', '40 DT', NULL, NULL, 'فوق 26', '28805907'),
(2951, 'بالحاج خليفة', 'هدى', NULL, NULL, '816gagsp', '$2y$10$sy8ykJFQowPVuJSDx8CxhuhaJEXDj6DIuPg60B4X2BpZGkoJQPK9y', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:35', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '97553795'),
(2952, 'عطية', 'محمد', NULL, NULL, 'acv420sz', '$2y$10$zJ8fNNX4X4IRuC6wMZcm/OCTY4/tv2vouHI9PofjgqrNqLJv55elm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:57', '20 DT سداسي أول', NULL, NULL, '13- 25', '25076096'),
(2953, 'بن حمودة', 'أنس', NULL, NULL, '3izp0fj7', '$2y$10$0dICh5kqqv.BzUgMlczC2.E7yoWlg0nYJsN09bl5vsXp6uty90Em2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:38', '40 DT', NULL, NULL, '13- 25', '58579726'),
(2954, 'حمودة', 'عمر', NULL, NULL, 'tlqlb5hh', '$2y$10$66Hmr2ky8rLfjyM1LqPoRuyT9CHI2Tkd73A1fUNU/YPjAZALJ6Bj6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:51', '20 DT سداسي أول', NULL, NULL, '13- 25', '52085164'),
(2955, 'حواس', 'رشيدة', NULL, NULL, '864fk9bu', '$2y$10$t7oj7sEocgbmVEUXTZurQ.d3CJqQWSvUfwJu55otHfRGhrL3k9QvO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:52', '40 DT', NULL, NULL, 'فوق 26', '53499621'),
(2956, 'ابراهم', 'مريم', NULL, NULL, 'deirofo6', '$2y$10$XyPBxBIfK0PZFslpfIdHVeEctlAG8jZRvv7icSkVGBBMyJOQ.CsqS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:14', '40 DT', NULL, NULL, '13- 25', '73259007'),
(2957, 'البكوش', 'اسلام', NULL, NULL, '5xzm35s8', '$2y$10$WoiVRGJ.lL0YmcumLTeVneZoQWwWMygxgbamFRrhmAhytdoEERxQe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:18', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '22900604'),
(2958, 'مناد', 'نسرين', NULL, NULL, '5xsjw98k', '$2y$10$3pJD1mWCBQ.XLyFWWv5OI.Hl7c/IK0tz.BepUOKrdAY4rp/abQXX6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:15:05', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '21465468'),
(2959, 'حواس', 'ضحى', NULL, NULL, 'kyzhvagj', '$2y$10$FaPYlTAikMi1u9vobMlZ7.A3f3yaXHRoAmqqglz5uPQu3iKiUGH3u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:52', '10 DT', NULL, NULL, 'فوق 26', '99357068'),
(2960, 'بوهلال', 'رفيقة', NULL, NULL, 'xuqyawa9', '$2y$10$aGeocLYQ7j0AOEq0GPtXbey8/2v0rBz.4OI6ERlg0AIqupKs5F14q', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:46', '40 DT', NULL, NULL, 'فوق 26', '98981517'),
(2961, 'ابن عبد الجليل', 'لطيفة', NULL, NULL, 'iiml2iyk', '$2y$10$G4Q6CgU5FwC90LuR8WcahuraGAEcCrkkT3YkpkQAHz7sxuAur6ZX2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:15', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '55996895'),
(2962, 'يوسف', 'محمد ياسين', NULL, NULL, '4yec15f2', '$2y$10$/eaEweQqFrPgncq0TfGeku19W5LbjqvPdUzipFs/aNmZDpeVkCpjm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:15:08', '40 DT', NULL, NULL, '13- 25', '20672135'),
(2963, 'الحامدي', 'شريفة', NULL, NULL, 'jqcrssj8', '$2y$10$vIvmsin3C8MxAH0mXrudAeGldj7NfSlLtrh8k6Lf.vaJ9LIA.BXbu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:20', 'معفى', NULL, NULL, 'فوق 26', '21729447'),
(2964, 'ميمونة', 'زينب', NULL, NULL, 'n6x5g23d', '$2y$10$LzFEdV1ufYszbhfGQYJGvOBN1nLGZNg10FG9G2z9sjvt7q2mNFiLq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:15:05', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '20617362'),
(2965, 'تريعة', 'نسرين', NULL, NULL, 'pzy8wok4', '$2y$10$lbPL3D2GB2J7zDD366rw4.P6zro9kWfJJJ.7zomEOGVUxM2XGfXmG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:49', '10 DT', NULL, NULL, 'فوق 26', '55979843'),
(2966, 'الشتيوي', 'فرح', NULL, NULL, '4tdezvyh', '$2y$10$jRk/AUA9bht91dwac9esR.WBmat1emG9PeFzWLUFnJnnrV2anJ8Ji', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:24', '40 DT', NULL, NULL, '13- 25', '58136186'),
(2967, 'العذاري', 'زهرة', NULL, NULL, '7rtys52f', '$2y$10$0SirqfYtJS8yPtvfwlHG7eQkpxai/RqKst4LZxv2c7wmwyBpgMOsS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:26', '40 DT', NULL, NULL, 'فوق 26', '97120748'),
(2968, 'العمروني', 'مريم', NULL, NULL, 'rwrrwfwb', '$2y$10$cdxHWA1KaOSnXHxAtMpkrO7DnILmBA0IW80XXT1w0gfc/L7oyAlNm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:27', 'معفى', NULL, NULL, 'فوق 26', '28827052'),
(2969, 'عجرود', 'بسمة', NULL, NULL, 's552zwss', '$2y$10$KRWjZoZBgSQEpTawQph9ze9YMvaCWF0Yvma0elEtK9xRZu41ALhWS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:57', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '97226366'),
(2970, 'هميلة', 'منال', NULL, NULL, '2p5xsasp', '$2y$10$hLVCUuf.9ecNmGEqp4lfkukbZd/9AJhtAbU0/slasiG36RfpjiFh6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '52872254'),
(2971, 'التكوري', 'سمير', NULL, NULL, 'jjmgell5', '$2y$10$SKhJb3tuSdvdngkIjjaV1.xRLNV2WK2KBCkk1d9P3RB6nIGxXPVme', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:18', 'معفى', NULL, NULL, 'فوق 26', '20195928'),
(2972, 'تياهي', 'عبد الرؤوف', NULL, NULL, 'm2ybz01e', '$2y$10$3H70GrANqJ3REcAXbW0akO9Xh19Ktq0WfuW9.xZN/z1C7blWdv9/u', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:50', '40 DT', NULL, NULL, 'فوق 26', '54420940'),
(2973, 'رزق ﷲ', 'رشاد', NULL, NULL, 'kuwzv72u', '$2y$10$y/Hk.5K1/7TY01CmbQ0I..kVQI4BzZdrxPG5tYFoj3T/4gyRYNHny', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:53', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '23827052'),
(2974, 'رويس', 'محمد أمين', NULL, NULL, 'f53j7xtr', '$2y$10$n3lhwxzvP9gh0NRmt4cLbObbzFn2utj8E.vwSX7mhFGoSQ.WHgxce', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:53', '40 DT', NULL, NULL, '13- 25', '93824794'),
(2975, 'بوقديدة', 'هشام', NULL, NULL, 'tjzxg9k0', '$2y$10$XqFxgiTLKAZxzzD0L9wg2eROd0Z7N5WuLHamowR1q7RWuYJZ41xwy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:45', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '58754883'),
(2976, 'دودو', 'محمود', NULL, NULL, 'ix9sv4gw', '$2y$10$z4CecGWX.4vG2Bjpt8OjmekzOaskgD8fguiw.lPdOhxu37hhjDEw2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:52', '40 DT', NULL, NULL, 'فوق 26', '23717537'),
(2977, 'ابن سالم', 'محمد علي', NULL, NULL, '1cgoq70x', '$2y$10$JqnQUNHyG8cdhgzfOp1OJuY2v/KIjjKYm2paQp1T1E2wkSVrMZoqi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:15', '20 DT سداسي أول', NULL, NULL, '13- 25', '56750734'),
(2978, 'غزال', 'لطفي', NULL, NULL, '3muve1au', '$2y$10$ekhkf19KcxheP6cWyWSMzee8OUrZ8Aioqi7DnrIG9sz3IDZMOIYYe', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:59', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '94327659'),
(2979, 'القارص', 'اروى', NULL, NULL, 'nh20nfpn', '$2y$10$dtgxxVkcu3SLyR24l5SCnOfoLmgnkJxXR67.ZK3sVrhPV7koz6gZK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:30', '20 DT سداسي أول', NULL, NULL, '13- 25', '28370072'),
(2980, 'ابراهم', 'نجوى', NULL, NULL, 'uymrc3qj', '$2y$10$FiEF1YrmH5ZMx98Dlgy1q.Tp6YSBgqV87AuMw0uu1IsLMLD/5LRHC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:14', '40 DT', NULL, NULL, 'فوق 26', '20448863'),
(2981, 'بن حمودة', 'اية', NULL, NULL, 'sq6fsokn', '$2y$10$rMYUTkrxsIDexa2DeTBfx.I4RkkoQTdFlY1srQsTuCDe6Ybu0oEha', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:39', '40 DT', '5218705467', 'سيرين الغماري', '6 - 8', '55626151'),
(2982, 'بن العربية', 'اسيمة', NULL, NULL, '2lmbi4ka', '$2y$10$Bqut0q/xy25oAuRwyg44Q.pW12xRDeJj88tJGZXN0WnIRqVr3MwHq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:37', '20 DT سداسي أول', '4213226928', 'برهان بن العربية', '9 - 12/ 13-17 (للحالات الخاصة)', '52732819'),
(2983, 'جرار', 'فارس', NULL, NULL, 's6e0hs9b', '$2y$10$vCbfEldAyjTsrLXVM6c02.q72vSKwEkqMLrEumudRtrabnj1QgvHO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:50', '20 DT سداسي أول', '8999059812', 'نوفل جرار', '6 - 8', '55490714'),
(2984, 'بن خليفة', 'محمد امين', NULL, NULL, '3m5ba4s2', '$2y$10$k9d7eQaMR4EisGKC77Ls9u.PqLGrt.JwrUvPKsscl5d7ykZUxJlEq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:39', '40 DT', '6282313417', 'عبير بن حمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '99620033'),
(2985, 'الغرمول', 'كنزة', NULL, NULL, '75zyzaus', '$2y$10$/wQ.4J6s6s7TjtTOxdXO8eFZvSbYVlHrhfP7Oj0dNiEUUAMiz4XSq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:28', '40 DT', '9707692504', 'عادل الغرمول', '9 - 12/ 13-17 (للحالات الخاصة)', '96542591'),
(2986, 'بن عبد الله', 'محمد خليل', NULL, NULL, 'sb42073f', '$2y$10$2QH9JstaTbEDFIlzdjOmD.NBmWhTNuUPo3sW9CQoKcDvcuBX7NbAG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:42', '20 DT سداسي أول', '1112244537', 'ضحى حواس', '9 - 12/ 13-17 (للحالات الخاصة)', '98783232 - 99357068'),
(2987, 'هميلة', 'ادم', NULL, NULL, '07ynenbs', '$2y$10$AbImYa2n3k4DhG9GG0DvPejKxdpz8DM.tFnsaBpaFzQ13yn8DOsDG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:15:06', '20 DT سداسي أول', '3949321553', 'حسان هميلة', '9 - 12/ 13-17 (للحالات الخاصة)', '22949412'),
(2988, 'العيدي', 'مؤمن', NULL, NULL, 'k92ot25c', '$2y$10$b3iUYgNzAQsR04ezy1OYy.pbqY2ObTfJ1Vv3HQSDYep4HBpk67/OK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:14:27', '20 DT سداسي أول', '3501773253', 'وليد العيدي', '9 - 12/ 13-17 (للحالات الخاصة)', '55979843'),
(2989, 'قلح', 'إدريس', NULL, NULL, '8vfej7fa', '$2y$10$XIrzb50UE9RbZIaxUIa.beSadq7tMMeJhv8DAIH2oPCgN03hVNYw6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:08', '2026-02-28 21:15:01', '20 DT سداسي أول', '9416895796', 'حافظ قلح', '9 - 12/ 13-17 (للحالات الخاصة)', '96689888'),
(2990, 'بن عبد الله', 'آمنة', NULL, NULL, 'y442n40v', '$2y$10$ojwQOTCV5PzBO8Wm4DqlruVe9an5z8PNWB3iGzIrA8KjUgmWSEnTa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:42', '20 DT سداسي أول', '4315919010', 'ضحى حواس', '9 - 12/ 13-17 (للحالات الخاصة)', '98783223'),
(2991, 'بلحسين', 'يامن', NULL, NULL, 'aeftl94c', '$2y$10$Vohk3k7cY4vb4ndZ0fuRDenRFCzGN4Se.w1kTJsTXxap/QRWnTjeC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:37', '20 DT سداسي أول', '9466219589', 'شكري بلحسين', '6 - 8', '79048975'),
(2992, 'تريعة', 'هارون', NULL, NULL, 'w904x0bj', '$2y$10$25/elxM2eT38EurdYYFii.uobWbPUF2pAFLLeOQ/T.0vdUT3dFvGu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:49', '10 DT', '9168823754', 'سيف الدين تريعة', '6 - 8', '55614819'),
(2993, 'بلحسين', 'ساجد', NULL, NULL, 'kkxgjxxq', '$2y$10$mpAzBCxpPBwjSkLZY4oHQ.Dew.9zmBYf.byVojFTG6ssdJQqRnuNe', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:36', '20 DT سداسي أول', '2687053479', 'شكري بلحسين', '6 - 8', '97048975'),
(2994, 'بن سالم', 'يوسف', NULL, NULL, 'fig34sld', '$2y$10$2ihmWdbfGWTSTxi9c8pYOO/wPjHB7CqMmJYuFpi3iyX5qEKHEX3UO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:40', '40 DT', '1976988928', 'نوفل بن سالم', '6 - 8', '22328360'),
(2995, 'بن سالم', 'عمر', NULL, NULL, 'kqst98q2', '$2y$10$PZyy8EMrMVjvVTv1OG6ep.p6pWEsv7L0JjwO7luItAlQ5KwEJ7G96', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:40', '40 DT', '5736883023', 'نوفل بن سالم', '9 - 12/ 13-17 (للحالات الخاصة)', '22328360'),
(2996, 'بو قديدة', 'مجد', NULL, NULL, '2fh5h8m8', '$2y$10$MLqGlIq7jgKvPNPgWNVSKO9uUDJ2O3Nc0jSLaVwAd7BK6gBzdP6Mi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:43', '20 DT سداسي أول', '1711689076', 'محمد بو قديدة', '6 - 8', '28304950'),
(2997, 'العبيدي', 'آدم', NULL, NULL, '1ujom5v2', '$2y$10$.gavTb2lSzagkZ5JOTRTVOJlia6Y86sDnKYjDkrwv3i3Ct34.Ox/G', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:26', '20 DT سداسي أول', '6948510590', 'وليد العبيدي', '9 - 12/ 13-17 (للحالات الخاصة)', '55979843'),
(2998, 'تريعة', 'أيوب', NULL, NULL, 'f8n7lbru', '$2y$10$6xlSTb1NndIL4c0U2j0vJ.KrcSEFmPuL9jvgRN.OAwh/TtVwFNC42', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:49', '20 DT سداسي أول', '5079411161', 'سيف الدين تريعة', '9 - 12/ 13-17 (للحالات الخاصة)', '55614819'),
(2999, 'بن عبد الجليل', 'آمنة', NULL, NULL, 'ec7y6tgv', '$2y$10$WgN.imUfj/8e39muJy71t.jldalgIKCl75/Fb76ZpH3nNwH53E042', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:41', '20 DT سداسي أول', '50991790', 'ضياء بن عبد الجليل', '6 - 8', '50991690'),
(3000, 'هميلة', 'اريج', NULL, NULL, '2mq5qvzj', '$2y$10$c.weaet0numR02PmNz1lE.w2.hqVPalUDeKAi08uW9jgH29ErRyMe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:15:06', '20 DT سداسي أول', '1401781995', 'محمد هميلة', '6 - 8', '98630489'),
(3001, 'هميلة', 'ابراهيم', NULL, NULL, 'ao28p7m6', '$2y$10$OrcQPWBhaokTm.JdnUIN2ux/qxV7gk4/DXafg3RlunBKlWnaanPrm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:15:06', '20 DT سداسي أول', '9233693314', 'حسان هميلة', '6 - 8', '22949412'),
(3002, 'الجلاصي', 'يوسف', NULL, NULL, 'ethqlvwn', '$2y$10$yuHcG9Ruyb0t8ImjcSwsgOcYd88iXB3oTIh2lAXezO6xjOZtHa6z2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:20', '40 DT', '1953161667', 'ايمن الجلاصي', '6 - 8', '20668416'),
(3003, 'ابراهم', 'انس', NULL, NULL, 'nidr9lz3', '$2y$10$ri9X71hO/J/zo5DPPIg/veNZg9900s0niesh9tRAlYqahiTRXydNi', '2026-02-28 22:16:47', NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:16:47', '20 DT سداسي أول', '9918426317', 'منى موة', '9 - 12/ 13-17 (للحالات الخاصة)', '23575711'),
(3004, 'القزاح', 'يوسف', NULL, NULL, 'zzegkhjp', '$2y$10$paHXeVVqo/T0QqAqu6ntDu9v2HHMmtSzhNQtRCRlk5r/1nHYm5.iC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:31', '20 DT سداسي أول', '4483282406', 'طارق القزاح', '6 - 8', '54323405'),
(3005, 'الزريبي', 'محمد ياسين', NULL, NULL, 'ypz7hvng', '$2y$10$NJJwRHvpSZnfOANbk44qjOe7Xz0vHZW.xcVj3AOrfX3ih6m0RUJVa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:23', '40 DT', '3633662739', 'إبراهيم الزريبي', '9 - 12/ 13-17 (للحالات الخاصة)', '23267421'),
(3006, 'غزال', 'ريحان', NULL, NULL, '8z2b2qmh', '$2y$10$LQ5FZlfeAEYEXWsvNfyH2eTfMs1hP8Xdk99ATmXxUpck7fap6fDUy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:58', '40 DT', '9171970901', 'ذاكر غزال', '6 - 8', '55537773'),
(3007, 'الحمروني', 'محمد حمزة', NULL, NULL, '1cglcy1s', '$2y$10$MzzItcAtHdymMi4hflfke.h2gL0idnNlW3tIL9ipE5IbD8vrFD41G', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:20', '40 DT', '6964818974', 'شكري الحمروني', '9 - 12/ 13-17 (للحالات الخاصة)', '94313406   /    24685641'),
(3008, 'جرار', 'فاروق', NULL, NULL, '0xg32o9c', '$2y$10$zS769GhVExC1FUSnUk/P9OxLAzrY0zW9hsOQunQB8hSXbU9mFrGn2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:50', '20 DT سداسي أول', '3929335109', 'نوفل جرار', '9 - 12/ 13-17 (للحالات الخاصة)', '55490714'),
(3009, 'قريرة الخذيري', 'إسراء', NULL, NULL, 'axtu18q4', '$2y$10$25JvmmPdHfuqROl6bIzhk.kEAihiaX1qZYFg.rILNERDCouJkyh..', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:15:00', '40 DT', '7117319628', 'فخر الدين قريرة الخذيري', '9 - 12/ 13-17 (للحالات الخاصة)', '98558879'),
(3010, 'بوقديدة', 'ادريس', NULL, NULL, 'o5kynebe', '$2y$10$NLqwg2qU5D9uZwN7Z2EHu.yZ6rxriolT979nm.It91JKeuBMmCdaq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:45', '20 DT سداسي أول', '3179935612', 'هشام بوقديدة', '9 - 12/ 13-17 (للحالات الخاصة)', '58754883'),
(3011, 'هميلة', 'اماني', NULL, NULL, 'y9uvxrfy', '$2y$10$XkbkdffW6B4iaLuteugOkeTFNtK5hIZOaJ7.mv2tyo5VkIUu8VEe6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:15:06', '40 DT', '1899169027', 'صابر هميلة', '9 - 12/ 13-17 (للحالات الخاصة)', '97597083'),
(3012, 'جرار', 'تسنيم', NULL, NULL, 'qdv7fp65', '$2y$10$X3odNLiMjcPIu5QfcOxuFeP3wGYXUmKLVzR5JVBIUl9KNQAKOraXG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:50', '40 DT', '4522564776', 'محمد علي جرار', '9 - 12/ 13-17 (للحالات الخاصة)', '52473013'),
(3013, 'عجرود', 'يسر', NULL, NULL, 'cy6994it', '$2y$10$lAQgUa0xACA8wKdGPBwVWO23QZwvGYDnA80pVRgQFIpOSifIBpHx2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:57', '10 DT', '4993539283', 'سفيان عجرود', '9 - 12/ 13-17 (للحالات الخاصة)', '28990534'),
(3014, 'الخذيري خذيرة', 'يحيى', NULL, NULL, 'qmp2d280', '$2y$10$Pv3rGdF0lrwlXh3TQEEZIuEvXdQsUV/CxkMfikYI08M3vfJo/ZyUu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:20', '40 DT', '7798175358', 'فخر الدين قريرة الخذيري', '9 - 12/ 13-17 (للحالات الخاصة)', '98558879'),
(3015, 'عجرود', 'أسيل', NULL, NULL, 'uqzquzuu', '$2y$10$bM7OaEWFqjuJyry.CvVsNel6VbWAVJsV.vGIRCKewgvNWcU4TEnaK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:57', '20 DT سداسي أول', '1477765565', 'سفيان عجرود', '9 - 12/ 13-17 (للحالات الخاصة)', '28990524'),
(3016, 'جرار', 'درة آمنة', NULL, NULL, '9q5p8ktp', '$2y$10$CjizraxY3N6B4mTHKiWWm.1c4IM1l1F1TRZXXY2pWxDFN9WOaBL..', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:50', '40 DT', '4896698325', 'محمد علي جرار', '9 - 12/ 13-17 (للحالات الخاصة)', '52473013'),
(3017, 'عجرود', 'سندة', NULL, NULL, '0p9pgmh1', '$2y$10$ItMVf3NAjeaOsk8YERqZBO7zfn2dI8ebdiT6cF1NIffm/yY1anP9y', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:57', '20 DT سداسي أول', '2958172624', 'سفيان عجرود', '9 - 12/ 13-17 (للحالات الخاصة)', '28990534'),
(3018, 'الغماري', 'صفوان', NULL, NULL, 'k3j7azj2', '$2y$10$7IpzQx/dmiwel/OJP4aEme/vMhEnhwxoF5HNzdyQkEX4CUHiai77q', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:29', '40 DT', '4733890996', 'رمزي الغماري', '9 - 12/ 13-17 (للحالات الخاصة)', '25435339'),
(3019, 'بن حمودة', 'احمد', NULL, NULL, '9soxpv6h', '$2y$10$RrUz9oFWg8kzcqRzLGAHvOYhdpg4zOzenzmkL9VHBpLFduKghoqom', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:38', '40 DT', NULL, NULL, 'فوق 26', '55921000'),
(3020, 'الشطي', 'علي', NULL, NULL, 'b112l0oq', '$2y$10$mT08/2YqVd6BRjxfd6R0UOBwd0.ufGWpntJ6sW65hZ/Cg/eQ1B6Oy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:25', '40 DT', NULL, NULL, 'فوق 26', '28645589'),
(3021, 'بن عبد الله', 'احمد', NULL, NULL, '93wujxai', '$2y$10$ok4qPTvtbv/lO1tC09pZ.ehNqSu57xHioUz57sFTl3zgIyyHffaXa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:42', '20 DT سداسي أول', '6790309285', 'انور بن عبد الله', '6 - 8', '98297824'),
(3022, 'الشتيوي', 'محمد أمين', NULL, NULL, '9htxxp3a', '$2y$10$uMfCk6mX2ly0yPAFqEj71Obm8jRbO/psMcHvcJTJEJBLl/QZqWVGi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:24', '40 DT', NULL, NULL, '13- 25', '52539307'),
(3023, 'الهذيلي', 'شهد', NULL, NULL, 'n8rkuitw', '$2y$10$5XzRRAbd1tWlifJfbkU4ZuNxp6JnojqncEw4mEr34z.XlgoS7kOci', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:34', '20 DT سداسي أول', NULL, NULL, '13- 25', '98131513'),
(3024, 'الهذيلي', 'زينب', NULL, NULL, 'vbe9x3og', '$2y$10$OWf.WjnA9WpgWxDP6E58vurMkg1aNPoVFnWdcQjMpKrXYn5SunBB2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:34', '20 DT سداسي أول', NULL, NULL, '13- 25', '58166814'),
(3025, 'بن حسن', 'ابراهيم', NULL, NULL, '4yh4whpp', '$2y$10$MPU/EEHGPew/Y9IbGcfyS.WvNWqfr7cSJ/LzDHHGrNhRkcBPDIfxm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:09', '2026-02-28 21:14:38', '40 DT', NULL, NULL, '13- 25', '29379846'),
(3026, 'زميط الشطي', 'ياسين', NULL, NULL, 'stp8m51p', '$2y$10$CFpdm2PYqdZ.XX1V/OdtcelojrB1CN0y8144slsJv0i6auRYTJXay', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:54', '20 DT سداسي أول', NULL, NULL, '13- 25', '40791144'),
(3027, 'غريب', 'أنس', NULL, NULL, 'q88c3dqq', '$2y$10$7q5w5wpmkzdAaC.Z7XqgUuiE7tq1aSpi9bEyuhKlGpI5tDqzs55HO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:58', '40 DT', NULL, NULL, '13- 25', '24096453'),
(3028, 'بن عبد الجليل', 'علي', NULL, NULL, 'fs1n7188', '$2y$10$Dvged1d90jKjwzUrBklVVOyxCC//TY4P0uYdOa7Hry1h3xVnf6d6a', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:41', '40 DT', NULL, NULL, '13- 25', '21211224'),
(3029, 'الاندلسي', 'محمد عمر', NULL, NULL, 'n1n6rphn', '$2y$10$uRBNmV1XyF10BOoUwuh07OlbK3vKyf653Wv2.Gq1ODmgOE2R5kPvO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:17', '40 DT', NULL, NULL, '13- 25', '20310150'),
(3030, 'شوشان', 'ابراهيم', NULL, NULL, 'ur30kmok', '$2y$10$UmBnI5RQ4TdHy/nReDT6xOEuKgrxo2rqOqauDoma3/h/rZ1D1m0nK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:55', '20 DT للعام الكامل', NULL, NULL, '13- 25', '23719210'),
(3031, 'التيس', 'محمد', NULL, NULL, 'm3arxauq', '$2y$10$.CwuogNjaGGfnKLLfRGLwOBDGkW1O2IwFCNnH.78t6xfqejUEmMfK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:19', '20 DT سداسي أول', NULL, NULL, '13- 25', '50531074'),
(3032, 'الاحول', 'فاطمة', NULL, NULL, 'e0pf83e5', '$2y$10$VVEbH/JXvk8v4Ls6qd9Vnu7iLD5sovzYb1sm3ajEPUMZNx4/pXEdu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:16', '20 DT للعام الكامل', NULL, NULL, '13- 25', '21164816'),
(3033, 'الجلاصي موسى', 'مصطفى', NULL, NULL, 'byh0h11y', '$2y$10$VeGsYNHDoCGDf/A60Q9P7.tUH3MiBFZSzC3DCGeRvpwi9J/u9NswS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:20', 'معفى', NULL, NULL, '13- 25', '97227667'),
(3034, 'الكعيبي', 'أيوب', NULL, NULL, '0ddlxqki', '$2y$10$8uqxYj0sJgUUJfsfHPakOOXQfWIDR1T0lw7HCXLHbe9hqpwBjZFNa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:32', '20 DT سداسي أول', NULL, NULL, '13- 25', '27707513');
INSERT INTO `students` (`student_id`, `last_name`, `first_name`, `middle_name`, `name_suffix`, `username`, `password`, `last_login`, `failed_login`, `custom_200000000`, `custom_200000003`, `custom_200000004`, `custom_200000005`, `custom_200000006`, `custom_200000007`, `custom_200000008`, `custom_200000009`, `custom_200000010`, `custom_200000011`, `created_at`, `updated_at`, `custom_200000012`, `custom_200000013`, `custom_200000014`, `custom_200000015`, `custom_200000016`) VALUES
(3035, 'ابراهم', 'تسنيم', NULL, NULL, '4uxek3rp', '$2y$10$2c4GhxYtx15WWPI2XH2MMO3LmZ59K2yi8pHU.TxbxGAwMR9h6CAMC', '2026-02-28 22:17:08', NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:17:08', '20 DT للعام الكامل', NULL, NULL, '13- 25', '24922444'),
(3036, 'بوهلال', 'فريدة', NULL, NULL, 'nb2tv3xs', '$2y$10$N7Nka3ghJBJ74rriZrYT2uoN.L7/2jfqQM3Quw3D0MdyYklbwk0Ai', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:47', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '50870575'),
(3037, 'موسى', 'هاجر', NULL, NULL, 'nz51v6aw', '$2y$10$eQjHo9RYubmc6wAizUZ5Ru7mCLHbW8boaOS29sN/OOsw7x/r4kvWu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:15:05', '40 DT', NULL, NULL, 'فوق 26', '99855208'),
(3038, 'هميلة', 'منى', NULL, NULL, 'ww70460g', '$2y$10$P/jHoVYtfDraduZ0J7j/fO5ZfpuB2j66fiWSh1v822vNGTzmduA0K', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:15:07', '10 DT', NULL, NULL, 'فوق 26', '50144872'),
(3039, 'هميلة', 'سامية', NULL, NULL, 'qn7h5g6l', '$2y$10$p6qbZQYlMMJRRi/yS962HethBZ1oDRL/.iYXji.V1HId1nGNwxnlC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '97451768'),
(3040, 'ابن عبد الله', 'منيرة', NULL, NULL, 'akmvucou', '$2y$10$9caHyt0x4ysF85FJ.BQYP.y6QD8xDzJZj.uwiVahCgeTP25aV17pG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:15', '40 DT', NULL, NULL, 'فوق 26', '22638517'),
(3041, 'بن عبد الله', 'أحمد', NULL, NULL, 'jlf6eyy5', '$2y$10$rzd0GZ73I/fj08JPTcNklOxyMQxTJnA/PObK0GCQK9sePmEXZ.wGS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:42', '20 DT سداسي أول', '6790309285', 'أنور بن عبد الله', '6 - 8', '98297824'),
(3042, 'الاسود', 'هندة', NULL, NULL, 'y2tyb5ma', '$2y$10$FnNoyfughMt0f7NIlg6uAOpaf/t81L7TPfBW3VD.tnEGw/OBD45Wq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:16', '40 DT', NULL, NULL, 'فوق 26', '20153018'),
(3043, 'رزق الله', 'سيف الدين', NULL, NULL, '7pud562y', '$2y$10$Xz8ihWND7bItaGyYiaMcIOxZRCLhEH/0//Jjcosy5bIB6HOuH5f7e', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:53', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '.'),
(3044, 'رزق الله', 'محمد ياسين', NULL, NULL, 'ncrcd34k', '$2y$10$nfnR0oAZQRqaF.N4kSf0HOVWhaRfVoUfJMRUUQFSHy5nfcerpRyOS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:53', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '.'),
(3045, 'بن عربية', 'أسيل', NULL, NULL, 'tou4k8bx', '$2y$10$UQXP7iLmX9ES5TgRgYU8UenXEAG6OxQu4eqnfbJ4/s9tIWwczBy.y', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:42', '20 DT سداسي أول', NULL, NULL, '13- 25', '52732819'),
(3046, 'قلولو', 'درة', NULL, NULL, 'ngm1om05', '$2y$10$UZzIshvJZTwhJuXof9fuR.0IbwIhSfE6hmMERzzxmAeJcI5S41Iy2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:15:01', '40 DT', NULL, NULL, '13- 25', '50545873'),
(3047, 'قلولو', 'دعاء', NULL, NULL, 'f77pwmx2', '$2y$10$6iFYyGBhrXD2O7kF.e9yyeAGfUaxDvY.juMEl0jkdoQsfWtREnsPS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:15:01', '40 DT', NULL, NULL, '13- 25', '56441036'),
(3048, 'كريفة', 'عائشة', NULL, NULL, '7a8i1oyd', '$2y$10$vNyyEBl6a.54OtphY5IFIeLKW8mEbkX.bfLzFq5Zc/wek5QkzkBK6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:15:03', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '23668134'),
(3049, 'الباش', 'أميرة', NULL, NULL, 'vmvc2f2j', '$2y$10$qYiI9cZJUXv3uiEhhD1Jo.9DxYIqvhiVy0rTk2jyANPq7ZApWsd3C', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:17', 'معفى', '6771007905', 'انيس الباش', '9 - 12/ 13-17 (للحالات الخاصة)', '27397003'),
(3050, 'الباش', 'أماني', NULL, NULL, '9it92jrl', '$2y$10$Ga61caZoYrie4p0isGPajusMg6W1n4r7QhpiACOeWtEBqSwNUnYy6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:17', 'معفى', '2876112240', 'أنيس الباش', '9 - 12/ 13-17 (للحالات الخاصة)', '27397003'),
(3051, 'الباش', 'أمنة', NULL, NULL, '6tuy37xn', '$2y$10$TnEOiaWUrKdByS9vkRYzFe.c1.TLhJJtUxnbqEXudUMAc./zAyUHO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:17', '40 DT', '6660051726', 'أنيس الباش', '9 - 12/ 13-17 (للحالات الخاصة)', '27397003'),
(3052, 'الباش', 'أمل', NULL, NULL, 'cbzxcmlx', '$2y$10$5/mxL4BAT5in/138DWkaAO5emAhrPwSo4l.UafnZBCTC0bcBGfAQ.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:17', '40 DT', '8763518651', 'أنيس الباش', '6 - 8', '27397003'),
(3053, 'الباش', 'آية', NULL, NULL, 'arpunn9v', '$2y$10$itR7h8m.W2.hrLiSuPGgRe7iaOu40Y.AXkPDAXZXCTO9JwuuuAm.u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:17', '20 DT للعام الكامل', '12918520', 'أنيس الباش', 'فوق 26', '97238115'),
(3054, 'الباش', 'آلاء', NULL, NULL, 'b4ygg0f8', '$2y$10$gAcEPYI.lLofez6WeVVpbuxoOuMaMe2XaRNDpzQC1uqjg79cBd0Ay', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:17', 'معفى', '12930777', 'أنيس الباش', '9 - 12/ 13-17 (للحالات الخاصة)', '27397003'),
(3055, 'بن حسن', 'سارة', NULL, NULL, 'uc3rtsnm', '$2y$10$DA2SoBBn2iqMDr7x4hAr6uODfuKHjJ0QxH8ESxJqN7KIVYKjttrq.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:38', '20 DT سداسي أول', '3090165675', 'يامن بن حسن', '9 - 12/ 13-17 (للحالات الخاصة)', '22769993'),
(3056, 'بن حسن', 'أسماء', NULL, NULL, 'g57hqz5r', '$2y$10$/X4Z8oHolv.9s8mEAbbt4uHjwAL/P62otGI7IEtVkMuk6eJ716beC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:38', '20 DT سداسي أول', '8639307525', 'يامن بن حسن', '9 - 12/ 13-17 (للحالات الخاصة)', '22769993'),
(3057, 'الشتيوي', 'فاطمة', NULL, NULL, 'vl1bmj7t', '$2y$10$67uIb/T0Ma/UQWQlkzDsPuwA4a1XOxjDiS8vKA46OlQUeP6P1L7ti', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:24', '10 DT', NULL, NULL, 'فوق 26', '22395932'),
(3058, 'حواس', 'يوسف', NULL, NULL, 'id6faipp', '$2y$10$18hXn6F7wUx5fQ25B8wjZuJO3De/JTZ1ecqB8VSDRUoDEK2.ukrWm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:52', '40 DT', '8962669755', 'رضا حواس', '9 - 12/ 13-17 (للحالات الخاصة)', '94667901'),
(3059, 'حواس', 'يحيى', NULL, NULL, 'ukjfiwwb', '$2y$10$T9c6IKFYU.ddJlTJEbi96.bJfLp5OYkbOSjWeDH4nEOkXl59oFShG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:52', '40 DT', '6387114439', 'رضا حواس', '9 - 12/ 13-17 (للحالات الخاصة)', '94667901'),
(3060, 'بو عرقوب', 'سليم', NULL, NULL, 'zpv4rqe4', '$2y$10$9MaNVEkeyC/XhnEU0dqma.ZDpIszwlo9ztheUMXB9KPRRDfsOKBIq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:43', '20 DT سداسي أول', '4790569009', 'أماني الصريدي', '9 - 12/ 13-17 (للحالات الخاصة)', '28896496'),
(3061, 'عمارة', 'مسرة', NULL, NULL, 'kcs5zd4o', '$2y$10$r5slVW7ezJ91YDbz49qjz.QZZXj1KGZmbGTroWiJ1PrIpq7hioFCO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:58', '20 DT سداسي أول', '8684921537', 'أميرة الصريدي', '6 - 8', '28081459'),
(3062, 'غزال', 'منية', NULL, NULL, 'p9mxg2rs', '$2y$10$RD7Lh86EkP7hfXWuUVr7Be2PuRHXZFQrv9MFJTe5Ky03XAN1RH7bO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:59', '40 DT', NULL, NULL, 'فوق 26', '95267957'),
(3063, 'يونس', 'نجوى', NULL, NULL, 'sm4gjihz', '$2y$10$yUMJpLqJnP5z9HQ3ltXnJuH3X/0.2Sioyfm6VKyIR09BNdWINKcGq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:15:09', '40 DT', NULL, NULL, 'فوق 26', '28563795'),
(3064, 'الأحول', 'عبد الرحمان', NULL, NULL, '6i8orze8', '$2y$10$EQDWwB8Iox1W9cc2vQ6RWuneH9YseL2LvKi/d8DBpk9lgXy7WqLUu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:15', 'معفى', '9592053952', 'محمد الاحول', '9 - 12/ 13-17 (للحالات الخاصة)', '22747749'),
(3065, 'الجلاصي موسى', 'فردوس', NULL, NULL, 'i0hbb3jl', '$2y$10$/QcOzPc/w2XjvfuuIDfLkeRiGLO5VncgdXDMRPp/bOCr3HVlkc5eC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:20', '40 DT', NULL, NULL, 'فوق 26', '50646772'),
(3066, 'الجلاصي موسى', 'تسنيم', NULL, NULL, 'id0s9k68', '$2y$10$M9kixK6sY1hh5l9q.pVmx.a3uriRSSCQsccEq6SfIvudl6BTWqdgS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:10', '2026-02-28 21:14:20', '40 DT', NULL, NULL, '13- 25', '50646776'),
(3067, 'بوريقة', 'سارة', NULL, NULL, 'q4zpl30g', '$2y$10$BFXOzCqX36109TytNhiXO.I00UdV9GW68UgN8qvFU0sOUNFX5y8RW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:44', '10 DT', NULL, NULL, 'فوق 26', '54880044'),
(3068, 'بوريقة', 'أسماء', NULL, NULL, 'thh2pdww', '$2y$10$p5Vy3wSuyiVj9SUlBQCpdedYlY.cnNCuoHzMNuMWQYDY1BjNuK142', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:44', 'معفى', NULL, NULL, '13- 25', '54880044'),
(3069, 'بوريقة', 'فاطمة شيماء', NULL, NULL, '1hc9my7c', '$2y$10$LNOjgCkBw18.Zbs7RAmZ4eEPAjuX.MLZ1Tf/9e6BvAnsDMWWhPj8.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:44', 'معفى', NULL, NULL, 'فوق 26', '29288370'),
(3070, 'بوريقة', 'صفية', NULL, NULL, '7mz5hj71', '$2y$10$yw3AXyKQR/R.a8UC5R.8fucB19FP7wKrYUDR2AJ1rPQvnzTbRga16', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:44', 'معفى', NULL, NULL, '13- 25', '54880044'),
(3071, 'العزابي', 'براءة', NULL, NULL, 'xg8x6c36', '$2y$10$wgvtV3wdsGkJRdr74QAbZ.QQOwTlM2bmrX0TvNfvii74iPjesemgu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:26', '40 DT', '5033897751', 'قيس العزابي', '6 - 8', '22357247'),
(3072, 'الميساوي', 'اسحاق', NULL, NULL, 't9q9ld4v', '$2y$10$GYTBZuO7nYZytPSFw/SxGeabPltLH2nBJAA/lC26mvFZ.Vuz2nsQ6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:34', '40 DT', '8406880468', 'اسماعيل بن العربي الميساوي', '6 - 8', '99108517'),
(3073, 'القاضي', 'الحبيب', NULL, NULL, 'f041irrw', '$2y$10$8sMSrM853M.cxGR04EMFdeYfx4lrRy1SH6ywATI/qx/JjCrDfWlD2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:30', '40 DT', NULL, NULL, 'فوق 26', '52957376'),
(3074, 'قليم', 'عائدة', NULL, NULL, 'dnenm390', '$2y$10$Q9gUGHyte9ob.0UZvFAu9.AYwkUYdun2hT6cXbExfooAT6ZdDL19W', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:15:02', '40 DT', NULL, NULL, 'فوق 26', '20400697'),
(3075, 'الزرقاطي', 'ملاك', NULL, NULL, 'k2ua0b8d', '$2y$10$HXmFOlkT8urtqMGVM2z.u.xLxq9krakbV3SqHzeS7hqKt6YjRJe.m', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:22', '40 DT', NULL, NULL, '13- 25', '52488880'),
(3076, 'الزرقاطي', 'لينة', NULL, NULL, 'tu8cafqz', '$2y$10$B.Xs/btSKNrSQwcjkc/eIOBQwRUHINpbjWu.4qJW16.itzxNFh77u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:22', '20 DT للعام الكامل', NULL, NULL, '13- 25', '25134800'),
(3077, 'الزرقاطي', 'اسراء', NULL, NULL, 'g0l5t0a1', '$2y$10$trf/A5s/B.g0Y5laWVa1zeEcfWhzETOkWF1AcomxS6n/Ze.eb/D7m', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:22', 'معفى', '9827931061', 'فؤاد الزرقاطي', '9 - 12/ 13-17 (للحالات الخاصة)', '20400697'),
(3078, 'الزرقاطي', 'آلاء', NULL, NULL, 'ohpyvpkw', '$2y$10$EgphhK0svy/JyOn9aZrdEuk9QUwZzIvZO6DgCuWe/CKL08g/DymCa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:22', 'معفى', '8243183672', 'فؤاد الزرقاطي', '9 - 12/ 13-17 (للحالات الخاصة)', '20400697'),
(3079, 'قليصة', 'علي', NULL, NULL, 'cfs4wdj9', '$2y$10$FQfp/bLPWKKLwBfu4RrCD.Cp3G/FIP7yW/XV1jutfyVokM25LZ8v2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:15:02', '40 DT', '4466442802', 'سفيان قليصة', '6 - 8', '95300616'),
(3080, 'قريط', 'ميار', NULL, NULL, 'ad4h3wzl', '$2y$10$fDqaQFf0dHzxc3R/D38SMeVNKq5zaReLc9onHDTAgTEHBcCmmZPwu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:15:00', '40 DT', '6807017840', 'مهاب قريط', '6 - 8', '23919700'),
(3081, 'عمارة', 'لجين', NULL, NULL, 'k61rnukv', '$2y$10$OiRZk4ypL6TiVza26yS9v.GPT4iTBC5joyugEn4g6dFLIQnytzMLi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:58', '20 DT سداسي أول', '4627990137', 'سفيان عمارة', '9 - 12/ 13-17 (للحالات الخاصة)', '96008584'),
(3082, 'الزرقاطي', 'ابتسام', NULL, NULL, 'gkknj9mj', '$2y$10$n0sqtx324Di6e.UcsPPvm.NJMul2tDK59xOgOv/XsID1bHV88v7kq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:22', '40 DT', NULL, NULL, 'فوق 26', '96054408'),
(3083, 'عاشور', 'اياد', NULL, NULL, 'qf2tj90v', '$2y$10$SSFZVoN4txkCx3zGLkgPPOoQmE5KlFdW/LwHrkFDyTV1mjHFxaKuO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:56', '40 DT', '9942407747', 'أحمد عاشور', '6 - 8', '97596999'),
(3084, 'الاقرص', 'أحمد', NULL, NULL, '2s0915ka', '$2y$10$L/9.RZ962Fd7Gtufi16Iju5Mb7Mk8QGel0tnEakFFd1YcKeEXqR5i', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:16', '20 DT سداسي أول', '8379914367', 'بشير الأقرص', '9 - 12/ 13-17 (للحالات الخاصة)', '20616614'),
(3085, 'الاقرص', 'مالك', NULL, NULL, 'g7l0bjlw', '$2y$10$Tw7NcRLCl7iKrEQYKONmjezTTICI2w33oS9g9Mxd/3fENX7vKmn4K', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:16', '20 DT سداسي أول', '4623045864', 'بشير الاقرص', '9 - 12/ 13-17 (للحالات الخاصة)', '20616614'),
(3086, 'الاقرص', 'يوسف', NULL, NULL, 'e7py3jgz', '$2y$10$JutypXnUrbyM.a9jxP06JOvNfv0/r0vkxtA2/umKspcyBmS6v.Y.W', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:16', '10 DT', '7571087648', 'بشير الاقرص', '9 - 12/ 13-17 (للحالات الخاصة)', '20616614'),
(3087, 'بلحاج خليفة', 'عائشة', NULL, NULL, 'f6w61g97', '$2y$10$wN.onAPzYH/1i7G4p08mhuZdaWCekdgMXQB3hHUjqWH1lPvuZLTGm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:36', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '27326972'),
(3088, 'بوهلال', 'ياسمين', NULL, NULL, 'y6npbge6', '$2y$10$8wLicNE.QNWpxA9c5FPzK.Y/sfHddI7YlOo0mC9NvCCWcYg6EWIKq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:48', '40 DT', '.', 'جمال بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '22922609'),
(3089, 'العشاش', 'سرور', NULL, NULL, '5tpmp7cl', '$2y$10$YwDz7BcomhBKkjl3quHlUO2w6BsAcqQoM9RG5pJPcX.3bK4JNYl86', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:27', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '96228709'),
(3090, 'القزاح', 'نعيمة', NULL, NULL, 'ylzf4raz', '$2y$10$f1Q.KB2qcqH7bnrJvM6NsOduxiBimSfngqnZEMQOLrbVxnAga.CzW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:31', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '98799044'),
(3091, 'المخينيني', 'هيفاء', NULL, NULL, 'jf90x70b', '$2y$10$4PzWqNavFJGBvtH4Xa4ZJOgNP0O2.w6ftQ9T3AB/hEfarzadgGKvi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:33', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '98297622'),
(3092, 'الساسي', 'أمان الله', NULL, NULL, 'taehinga', '$2y$10$tTeZ0qYJwxdLUzcWq4SrZOKKRZT18aTbrr8J.iocCp1jLm9EvysLm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:23', '40 DT', '7875119930', 'طارق الساسي', '6 - 8', '.'),
(3093, 'اللبان', 'نوران', NULL, NULL, 'ior33k8e', '$2y$10$r.405fnkeiMCCi8OYAsmaeyAohAE8t7Ec..5Neiv3B2znr3UVtA86', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:32', '20 DT سداسي أول', '7159389033', 'خالد اللبان', '9 - 12/ 13-17 (للحالات الخاصة)', '55429172'),
(3094, 'غريب', 'زهرة', NULL, NULL, 'igilk693', '$2y$10$2fC29mLyaR3gB2PjmArk/u7v/fsO.9o8XlLMx7cvTxjIP76V6PoPW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:58', '40 DT', NULL, NULL, 'فوق 26', '54466361'),
(3095, 'بن خليفة', 'آمنة', NULL, NULL, '06hzmtz3', '$2y$10$UIC9bPbX9zIYXLCQEmivrOEN7kOGWwqZUp/Pck/wdRTno8H3PwoxS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:39', '20 DT سداسي أول', '5069493154', 'عبير بن حمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '99620033'),
(3096, 'بوهلال', 'ليلى', NULL, NULL, 'stklw12r', '$2y$10$M4AgUsstbhHJ68Ay.5FZOuNESHSV4wl0nakQgmjWPZuahtDzc.BXq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:47', '40 DT', NULL, NULL, 'فوق 26', '99408666'),
(3097, 'عليبي', 'عمر', NULL, NULL, '3qjkoltf', '$2y$10$IL5JX6aRqPYNu1b3wH3dz.TzU/dcKlPsHXSjgq5AmibsYdp1kca3m', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:58', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '50559095'),
(3098, 'بوزموشة', 'ايوب', NULL, NULL, 'ozc8ss2g', '$2y$10$QfrYvJxLK1OCbB07Lhbxd.9e.UIfIIxZZJREYb7xewspY1xNfzpa.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:44', '20 DT سداسي أول', '1185402543', 'مديت بوزموشة', '9 - 12/ 13-17 (للحالات الخاصة)', '23868870'),
(3099, 'بن حمودة', 'ياسين', NULL, NULL, 'hxpfz8n7', '$2y$10$F51b/OHl3jrsVUqFSA0.4euLl.gsqVF2N57R2Rmv10tcNgLCLrBaK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:39', '40 DT', NULL, NULL, '13- 25', '6'),
(3100, 'بن حمودة', 'حمزة', NULL, NULL, 'd8rqtr04', '$2y$10$sx1udz7nkwo8uvTKQsXrPObLWIoKHPjfwAG6FP4P.gHoYDciGmQMi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:39', '40 DT', NULL, NULL, '13- 25', '6'),
(3101, 'بن حمودة', 'احمد', NULL, NULL, 'vwq51oky', '$2y$10$H7p30flEam0g4rTddBiNn.Zu8qOj47ngrs6d819U3.ku2jMsRyt5W', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:39', '40 DT', 'ت', 'مصطفى بن حمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '6'),
(3102, 'بن حمودة', 'ابراهيم', NULL, NULL, 'khq4yzz2', '$2y$10$9iaTTNyTZPyxG/HsLJpiPOR6Rxn8DQZeWSC5squa4WrRTFyPPv4BW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:38', '40 DT', '6', 'مصطفى بن حمودة', '9 - 12/ 13-17 (للحالات الخاصة)', '6'),
(3103, 'عاشور', 'نجاح', NULL, NULL, 'w5yr348v', '$2y$10$BP8n/KHU3uVws8rfoHns7us.B.BT.fNNQ5lb4/IVeenzIQr8pNHQ.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:56', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '.'),
(3104, 'سعد', 'جاسر', NULL, NULL, 'w7sbutjr', '$2y$10$/KHBxGnw3Ipd7XcSKWcqmOgczgH.PlXQ93dRDiq5EZhboMHnPABS2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:55', '20 DT سداسي أول', NULL, NULL, '13- 25', '28420587'),
(3105, 'بوهلال', 'محمد ياسين', NULL, NULL, 'a2zof88l', '$2y$10$sDpgfzDvRDyJNhzV5bOIbehRoxXtw7cVXiMX6vcvyQc6pIr90fVIC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:47', '40 DT', '2673581694', 'رياض بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '20520408'),
(3106, 'بوهلال', 'شيماء', NULL, NULL, 'whhsgw98', '$2y$10$UVH1AMB1Uv6JQ3id4Nq5tuMeAXFyb2nIyJFAxUe33fXvRQFzkdy4y', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:47', '40 DT', '1596133178', 'رياض بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '20520408'),
(3107, 'الزرقاطي', 'هشام', NULL, NULL, 'md7c852f', '$2y$10$Xt2UV25SWklGFQhbMO.zkemWq/N3yGwZ8EzJ7cGhqzgiK2.KES/fy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:11', '2026-02-28 21:14:22', '40 DT', NULL, NULL, 'فوق 26', '50350786'),
(3108, 'الزرقاطي', 'احمد', NULL, NULL, 'f7msople', '$2y$10$BGbc7Ed.Pf8rNrkPwrsPI.cPJ2IdjBvYulCVMrKu0plqL7v3PwJhq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:22', '40 DT', '6956876675', 'هشام الزرقاطي', '9 - 12/ 13-17 (للحالات الخاصة)', '50350786'),
(3109, 'الزرقاطي', 'جاد', NULL, NULL, 'ujuwtuyw', '$2y$10$0g87k26sa/r8CeMZfcMYTuTI1gmzdv/ZJGJXycRkCMOXjpbOYDoZS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:22', '20 DT للعام الكامل', '8049465982', 'هشام الزرقاطي', '6 - 8', '50350786'),
(3110, 'الأندلسي', 'فاطمة الزهراء', NULL, NULL, 'g14cqznq', '$2y$10$RfyiBNfDYKE3gYwGxtlyR.OhqkM68XIWLfgF.bhH4X0TEA8wgv12i', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:16', '40 DT', '7579815704', 'وفاء فلفول', '6 - 8', '50519498'),
(3111, 'الاندلسي', 'محمد الصادق', NULL, NULL, 'dwtxo8vk', '$2y$10$.fOdKQWyhnBZj6GYFcHg3uS7091XtdIZMsmQa1xKdqeeM5bgFCwre', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:17', '40 DT', '5330675416', 'وفاء فلفول', '9 - 12/ 13-17 (للحالات الخاصة)', '50519498'),
(3112, 'قعيش', 'امال', NULL, NULL, 'ji63c7qw', '$2y$10$nhDv9ROqF44VXKsQ9Bc4Musmzh4pn/WfkfZwcOuXkbZfqyJT599D.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:01', '40 DT', NULL, NULL, 'فوق 26', '50334964'),
(3113, 'الأندلسي', 'نور', NULL, NULL, 'cvpg6sx2', '$2y$10$spemb4rHp2ppCWFYTnSQTOfT2U.4P8NCecQJwxNgIZdXOhPDhn4YS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:16', '20 DT سداسي أول', NULL, NULL, '13- 25', '29164361'),
(3114, 'هميلة', 'شريفة', NULL, NULL, '34tdlkf6', '$2y$10$vxxqLTqhXDQ.5fAqXV9szuRBRSPpdgufmhn/meOOJCEXsbipPEqa6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:07', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '24123533'),
(3115, 'الدهمول', 'اسماء', NULL, NULL, '81xrliwo', '$2y$10$lcdM1I6XfzGjRs0maAoDguzLawo5W2D4vdksgfLezuU2BhAnsWDQ.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:21', '40 DT', NULL, NULL, 'فوق 26', '.'),
(3116, 'قلولو', 'ياسمين', NULL, NULL, 'hjab93ib', '$2y$10$VTYqADZOItznh.olE3QXF.Dx3Zfkc2pAryO0WjaRC4CNKmRD0iOm6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:01', '40 DT', '2436903572', 'على قلولو', '9 - 12/ 13-17 (للحالات الخاصة)', '.'),
(3117, 'قلولو', 'أميرة', NULL, NULL, 'imh9t7a4', '$2y$10$1ZJ1EW.pNB0Y4d9sw3p92e1LtW5.UzwuqUpryD55RuhovdMefpuKO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:01', '20 DT للعام الكامل', '7665813808', 'على قلولو', '9 - 12/ 13-17 (للحالات الخاصة)', '.'),
(3118, 'قلولو', 'ملاك', NULL, NULL, '9ru5n199', '$2y$10$YKIBHXMv2IWPH2lcjWDLReBEPouCDEr/heRT9MyK6TSijtkZ5myhm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:01', 'معفى', '7375070553', 'على قلولو', '6 - 8', '.'),
(3119, 'بريري', 'آمنة', NULL, NULL, 'f9uuntug', '$2y$10$XnY43lunDPfSHxGyOtjfyuZi88cnsUnORo35TxeqYEkW8BqqCoQHK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:35', '40 DT', '9761245796', 'مجدي بريري', '9 - 12/ 13-17 (للحالات الخاصة)', '98983183'),
(3120, 'بريري', 'احمد', NULL, NULL, '07h1hgsw', '$2y$10$pLXwOTChRKHrgZe0hdxAsepfSgzWPrYHyoPV2JHJ48xCmJBMSlAZS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:36', '40 DT', '8528028923', 'مجدي بريري', '6 - 8', '98983183'),
(3121, 'قلولو', 'عمر', NULL, NULL, 'uggei66x', '$2y$10$DqxerwMUVxu635TBN0aGwO482YqPJqBYwgzO0c/YDbGtGUguxWwhe', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:01', '40 DT', '2872060266', 'عبد العالي قلولو', '6 - 8', '27701000'),
(3122, 'قلولو', 'لجين', NULL, NULL, 'w0jb3cs1', '$2y$10$ww5vWWtua2prWxnd2e7H3uEJ5nFlbFS.NpHBtS2peBUgKaB7YfKIm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:01', '40 DT', '4996718459', 'عبد العالي قلولو', '9 - 12/ 13-17 (للحالات الخاصة)', '27701000'),
(3123, 'قلولو', 'لينة', NULL, NULL, 'ocoyu9ve', '$2y$10$9lfH398mFw1kvixL40osu.9RHoW.iSxKplpewKYKrN1KzG/PdNVvK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:01', '20 DT للعام الكامل', '1258446068', 'عبد العالي قلولو', '9 - 12/ 13-17 (للحالات الخاصة)', '27701000'),
(3124, 'عجرود', 'بيسان', NULL, NULL, 'tra7st94', '$2y$10$oenWoQ5m4C//GQex2wXl6.BxrE5DUbl5KtghA2hSsG0ibGLvqDukq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:57', '10 DT', '6793528776', 'ناجح عجرود', '6 - 8', '24838651'),
(3125, 'كميمش', 'عائشة', NULL, NULL, '3m93t4lb', '$2y$10$HmLQCkc9JVDR.R4fyl0Oiup15jnsm45pokLIKk3.GEDt8tYkFmdfa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:03', '10 DT', '5945727266', 'محمد كميمش', '9 - 12/ 13-17 (للحالات الخاصة)', '98184466 -  54667094'),
(3126, 'التليلي', 'شهد', NULL, NULL, 'ym0yfal9', '$2y$10$6AZVvW9AfWF4VFYhCe/TCu0BjT9OvbClev81cfctMWlN3HJGwJszi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:19', '10 DT', '9789411566', 'مهدي تليلي', '9 - 12/ 13-17 (للحالات الخاصة)', '2007112'),
(3127, 'التليلي', 'يوسف', NULL, NULL, 'qf7yb9qz', '$2y$10$VCLKuKk8WF.Mn2fvpR3rL.iQ0GUqYDPLnhVoYTCu0ffvpCXeLbduW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:19', '10 DT', '8146702018', 'مهدي التليلي', '6 - 8', '20071112'),
(3128, 'التليلي', 'رتاج', NULL, NULL, 'viobhsfg', '$2y$10$DMPYg.hZiU5VhTrCfZUdSuqNQG/RaSwQ4Brvkn8VbUWcYHp7dGMg.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:19', '10 DT', '6516885281', 'مهدي التليلي', '9 - 12/ 13-17 (للحالات الخاصة)', '20071112'),
(3129, 'مباركي', 'اياد', NULL, NULL, '5ryopu1e', '$2y$10$Hx5tfWf7i.HQSGKWLUb9jelRmle/ACyj4ALaV7soHccbkZu4V8cC2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:04', 'معفى', '2797455142', 'فيصل مباركي', '6 - 8', '24499422'),
(3130, 'العزيبي', 'يوسف', NULL, NULL, '3rwcxzsx', '$2y$10$DHvnRmJshK3IZA2VxU5qy.6elRfnrR3KvWQoRTwVDGxvOy/OACyuO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:27', '20 DT سداسي أول', '5744965850', 'سالم العزيبي', '9 - 12/ 13-17 (للحالات الخاصة)', '23125991'),
(3131, 'بوهلال', 'اسراء', NULL, NULL, '6vuimm2r', '$2y$10$67GBDsRtR85QUunZ8ZexqOT5LBk.VMA4zDs4SrU64svpRV8LK/EzC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:46', '10 DT', '1907425174', 'عزالدين بوهلال', '6 - 8', '98202414 / 97479747'),
(3132, 'العمدوني', 'تسنيم', NULL, NULL, '4fe89hmq', '$2y$10$ULb0TiJMg3CYqvSk8a11cOfCib3f.4mi1RIEPPpbcE7QnsyH6Yp8u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:27', '40 DT', '1262863175', 'محمد العمدوني', '6 - 8', '92219584'),
(3133, 'براهم', 'آزر', NULL, NULL, 'pl1s8z4v', '$2y$10$TQ1iONavdjParK/3jyW9x.GZTG0pjiWe3uQMe1c06hV97N0suE6Pu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:35', 'معفى', '8534097079', 'محمد نزار براهم', '9 - 12/ 13-17 (للحالات الخاصة)', '26316'),
(3134, 'بن فقيه علي', 'سجى', NULL, NULL, '776akf8z', '$2y$10$zDHkDZ6I5pcqCCjZESG0W.bmNWCVhYtj4vm1aBaZkR97yDtk74x1W', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:43', '20 DT سداسي أول', '2363235854', 'صلاح بن فقيه علي', '6 - 8', '22902614'),
(3135, 'رياشي', 'لندة', NULL, NULL, 'dd2bhw8b', '$2y$10$t8OXiCdYFQamv1/grVtqU.UCk6sQv37QBnbcxbgxYPJ.okqL4SBP6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:53', '40 DT', NULL, NULL, '13- 25', '52552389'),
(3136, 'قعيب', 'ندى', NULL, NULL, '1ngyidpg', '$2y$10$.j7rwVOkqch.b7H6Ywc9ouoX89AtKj1M0AuWAyYFnigOpRT2nOicq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:15:00', '20 DT سداسي أول', NULL, NULL, '13- 25', '46900803'),
(3137, 'الزناقي', 'وائل', NULL, NULL, '6haolcki', '$2y$10$NGclfe4e/Q1ILNlu3Zf7Be1b7EqzqeMZV.XqBoNQfgRcnP8wZnJRu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:23', '20 DT سداسي أول', NULL, NULL, '13- 25', '28052958'),
(3138, 'علوان', 'فوزية', NULL, NULL, 'gf92yq53', '$2y$10$LeC7GCjjTGE4B9b6btTEguvS7dde6CKYGDmkQ3tuyrlhBzf2vEsTW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:58', '40 DT', NULL, NULL, 'فوق 26', '0'),
(3139, 'القزاح', 'عواطف', NULL, NULL, '7nu6ryl9', '$2y$10$S9a71sTc/kSzyv5VZL/AHeTl78hVbh09qzYZzX9ffn/R55OxyDnmC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:31', '40 DT', NULL, NULL, 'فوق 26', '24056968'),
(3140, 'رويس', 'ميساء', NULL, NULL, 'eanehv1y', '$2y$10$MsFMKQ0/wM8nDgClcC.db.1uKW5.mzvsaP0X/O844EUfU67cxIzbC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:53', '40 DT', NULL, NULL, 'فوق 26', '24450850'),
(3141, 'تريعة', 'عبد الرحمان', NULL, NULL, 'kexqrmx7', '$2y$10$CbUh1k8rUAlIQ.U0b.9hEuARUrLncvWp0.jwnjVCsw9pDZ7wkYcv.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:49', '20 DT سداسي أول', '8783773362', 'ابراهيم تريعة', '9 - 12/ 13-17 (للحالات الخاصة)', '53743352'),
(3142, 'تريعة', 'شيماء', NULL, NULL, '7g1nd22x', '$2y$10$zvN020wJOyzOV1PpJE11zeLgCCo89YhhK5GuVJrmZF3oPHe7j2r4q', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:49', '20 DT سداسي أول', '5847536276', 'ابراهيم تريعة', '9 - 12/ 13-17 (للحالات الخاصة)', '53743352'),
(3143, 'بوقديدة', 'رحمة', NULL, NULL, '20o6ncvg', '$2y$10$vhSnCk/NfSJnd4YmRM1p5uyuixkWfauvyp36kMdNV0l/8eOmNGq.e', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:45', '10 DT', NULL, NULL, '13- 25', '57754883'),
(3144, 'براهم', 'نور', NULL, NULL, '21g3a7fj', '$2y$10$G9Ck60DNd/lu2ejfHWJBIeGdVKvaXVtNPkCQkOuoVQFd5w2vGFTlu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:35', '20 DT سداسي أول', NULL, NULL, '13- 25', '22954393'),
(3145, 'سحيب', 'نجوى', NULL, NULL, 'lwy9o6fq', '$2y$10$IQpqDuR.LE5b996SU9/BResCJ6jx8f56bhKP6S/.tG.KtloNkvMai', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:54', 'معفى', NULL, NULL, 'فوق 26', '42292212'),
(3146, 'بن عبد الله', 'يسرى', NULL, NULL, '24x4ovir', '$2y$10$/fBfHoWf2jZqQc0DE0Qqm.oof/80Z3xt7gcLWVYXs8lq2ZBWeydRa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:42', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '54251245'),
(3147, 'بوسعادة', 'احمد', NULL, NULL, '46vx2pvj', '$2y$10$mh0/jBAJ8L9S8oLv/opR5uMeolbK5TbGjgaNwfHXrxUJJ0t5zT1VK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:44', '40 DT', NULL, NULL, 'فوق 26', '26402402'),
(3148, 'بوهلال', 'محمد ريان', NULL, NULL, 'ju5t8zbn', '$2y$10$x1UxtD4TVxE0ETawQQVf6uk0zEAx2UrM/EuPzFzYjXjc1swUSYmre', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:12', '2026-02-28 21:14:47', '40 DT', '4519585765', 'محمود بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '52370358/ 20199195'),
(3149, 'بوهلال', 'ياسمين', NULL, NULL, 't5ald7h9', '$2y$10$9lTkUJESWoFmHuNoDZggb.u7QclTf5wRpPJJz3fueGQK6iozeS1tG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:48', '40 DT', NULL, NULL, '13- 25', '20199195 / 52370358'),
(3150, 'بن عبد الجليل', 'محمد', NULL, NULL, 'kzjsytxu', '$2y$10$papq4hElbLMHejUuOqu.FeMP7MOXBZabcPD3YSe6z3BHcm9u/9ISm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:41', '40 DT', NULL, NULL, 'فوق 26', '56344683'),
(3151, 'يوسف', 'روضة', NULL, NULL, 'zoi4e204', '$2y$10$HLUesYn/pNCcEZnop0h1y.5QXDxg/EPYQC74qBuRo1TJ2fT2eW7xe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:15:08', '40 DT', NULL, NULL, 'فوق 26', '55020752'),
(3152, 'بن الحسن', 'ايوب', NULL, NULL, 'i2a2zr1v', '$2y$10$Yeja7TNGuzLQItms0ePLj.FyR6mB706SOjby84UDKe11oho5qK2Ta', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:37', '20 DT سداسي أول', '7358011283', 'حمدي بن حسن', '9 - 12/ 13-17 (للحالات الخاصة)', '29038131 / 95871168'),
(3153, 'جرار', 'كلثوم', NULL, NULL, 'xttcxt27', '$2y$10$ADasugVIWuXBTqWYbQYzze9G1OD7Zy8Ttts6/yXZi0jW0GldQMbeu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:50', 'معفى', NULL, NULL, 'فوق 26', '95871168'),
(3154, 'ذكار', 'ريحان', NULL, NULL, 'kmdhrxlp', '$2y$10$QmqBEgeZJNI0Le4upkdYj.HGY6sCOmqHXyYaTrm4UX3pd/Gqc2WeW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:52', '40 DT', '1476263006', 'سامي ءكار', '6 - 8', '98284199'),
(3155, 'المجدوب', 'سنا', NULL, NULL, 'ftratnaa', '$2y$10$2BedK5qb2P0QiLJpw9sebuR55xsaN2Lan0LkZMSciOSIg8LdUyu3W', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:32', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '28886326'),
(3156, 'موسى', 'لمياء', NULL, NULL, 'gtlsf0gi', '$2y$10$5irhDp0nxiwr67WAkmtoIuQHb.3eo3q5p6k94ka15ps2slz6rAGjS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:15:05', '40 DT', NULL, NULL, 'فوق 26', '97597604'),
(3157, 'الشبلي', 'نعيمة', NULL, NULL, 's8oq2ecz', '$2y$10$aV7y0QiHkeaGHibHvYCHl.LmMGsmIoRg/ziVQPo65G9uAmfQzghNi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:24', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '20619752'),
(3158, 'بريري', 'مريم', NULL, NULL, 'nglfi5mw', '$2y$10$3cxwepWuMM3YpVPijVrWgOeFctNFZwstxdJ0jr8OlWMQlHUF1pLfO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:36', '40 DT', '3497199402', 'شهاب بريري', '9 - 12/ 13-17 (للحالات الخاصة)', '99630844'),
(3159, 'بريري', 'سارة', NULL, NULL, 'muq3svqy', '$2y$10$dyV8DJ/0ffITZ64Jibr3JOv6xt6K2QQ57mAMQ/ARQ62a.5LoidAj.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:36', '40 DT', '8588539240', 'شهاب بريري', '9 - 12/ 13-17 (للحالات الخاصة)', '99630844'),
(3160, 'بريري', 'عائشة', NULL, NULL, '9qqadl0z', '$2y$10$.8DkQSIWMY1T8nM63pllA.CIsnahOsq5gMnBVxwAUzGhWToMcL0Mm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:36', '20 DT سداسي أول', '6211025083', 'شهاب بريري', '9 - 12/ 13-17 (للحالات الخاصة)', '99630844'),
(3161, 'ابراهم', 'محمد عزيز', NULL, NULL, 'bv6tulsd', '$2y$10$fWEj4YLskkW1ayomkqPo6e2U13MR./hWcIOm5D9x705dtgCoNtrfG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:13', '20 DT سداسي أول', '9085236127', 'محمد نزار براهم', '9 - 12/ 13-17 (للحالات الخاصة)', '26316831'),
(3162, 'بوهلال المعموري', 'لطيفة', NULL, NULL, 'b59y7soi', '$2y$10$SXLgRFyHcV3ebc5ZTnQpYu6Q8zaQ/VVqTu0GlzkBYomBsnMYO9abK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:48', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '24092555'),
(3163, 'بوهلال', 'بشيرة', NULL, NULL, '5sl9ls4g', '$2y$10$rDSpav1hWRQSf/XRKjFfluu7iTgEe2K3CFsxzt6orMmGchhUks3vm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:46', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '23403277'),
(3164, 'النويقش', 'لطفي', NULL, NULL, '9u5k31aa', '$2y$10$bwOoL0OOwvkPSJ3ojdgEH.uZ6fdyZpJQz2XvsCW0BatVSIQfDJLxa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:34', '40 DT', NULL, NULL, 'فوق 26', '97403975'),
(3165, 'النويقش', 'يوسف', NULL, NULL, 'gbhxf4nt', '$2y$10$x68tySQa4VP7JTtEJcGa2uMmrR4b3uCgjOYyHFRbWlNbm1Vvl82A2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:34', '40 DT', NULL, NULL, '13- 25', '97403975'),
(3166, 'النويقش', 'عمر', NULL, NULL, '4v4e53ib', '$2y$10$uqygzhrh.zprX/j.bXMOyOjntfz89JgSqfSeP/Hk2oHOxlf1QCZv.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:34', '20 DT للعام الكامل', '3664564616', 'لطفي النويقش', '9 - 12/ 13-17 (للحالات الخاصة)', '97403975'),
(3167, 'النويقش', 'اسماعيل', NULL, NULL, '5fca8cz7', '$2y$10$LwdOelEXX8lw5XrFjjkLPejkZKzHwxJ2UAQuhe25hu8zTbAMOwGCu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:34', 'معفى', '3657166950', 'لطفي النويقش', '9 - 12/ 13-17 (للحالات الخاصة)', '97403975'),
(3168, 'السعفي', 'شيماء', NULL, NULL, 'gzkcmj1u', '$2y$10$ecUX4k..wUVxWEraCGRYP.UWkUBnn8jFnUS2aKkOnwiR1HLZ9YRg2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:23', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '21304628'),
(3169, 'الميداسي', 'ليلى', NULL, NULL, 'bo34bp7n', '$2y$10$nNBVzhoDvKtfIq.B2mMYQOU46plkERfxFfCSrfa7nB/1sTmdzvQRK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:34', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '25144773'),
(3170, 'المخينيني', 'لينة', NULL, NULL, '5yn8fasw', '$2y$10$xJ2QyJVXIvEEC/2GdFm9kepD2KFyxdatmI0Y8Lx8i4HL6d50YFXCS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:33', '40 DT', '4707204983', 'عارف المخينيني', '9 - 12/ 13-17 (للحالات الخاصة)', '27141296'),
(3171, 'ابن حسين', 'آمال', NULL, NULL, 'q0lx4swr', '$2y$10$P293JpGt6b0q/I440qFgOu4erPCmYC2Agx39uHpp91UjEOiBkL7pW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:14', '40 DT', NULL, NULL, 'فوق 26', '58386780'),
(3172, 'قريرة الخذيري', 'صفاء', NULL, NULL, '8ys3k303', '$2y$10$DE7w1LWf21AhlvtInYaZV.ln6Wm7x5Ae5/LMBqPYJleFflH5Rq.t.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:15:00', 'معفى', NULL, NULL, '13- 25', '98558879'),
(3173, 'الصغير', 'وسيلة', NULL, NULL, 'lkulkkth', '$2y$10$PT8EcBfWlSmix8uWLNqr3eMQpNNaV4.v0rB8pDbZapxkWG3X2kvgO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:25', '40 DT', NULL, NULL, 'فوق 26', '95737089'),
(3174, 'زروقة', 'احمد', NULL, NULL, 'v6sqv07l', '$2y$10$zfXgJY/fRi0ZTg8Qv051K.3vAWdY7suB.iIEO8YDXcsNLsIgsGNKW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:54', '40 DT', NULL, NULL, '13- 25', '53735520'),
(3175, 'سلامة', 'محمد امين', NULL, NULL, 'mx0m3qep', '$2y$10$gPyK8FXhC57eyv2vx6s5O.eEXpguHVIFb7IfAsmK/prS4E3sqRpsW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:55', '20 DT سداسي أول', NULL, NULL, '13- 25', '95671529'),
(3176, 'الدوس', 'عفاف', NULL, NULL, 'ii7ryd8a', '$2y$10$AuK4jE5s0Ump//MPOlTb0Oe.vtkvH2ODmWVJLcKbxE.kujMP63H0u', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:21', '40 DT', NULL, NULL, 'فوق 26', '25224848'),
(3177, 'بن الفقيه علي', 'فاطمة الزهراء', NULL, NULL, '9m0n37zk', '$2y$10$/7Tqdpj0UWhzspbdTnRbE./Qbp/jP5w4Hljj4RTSxV01BDJdwEhzm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:38', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '46450707'),
(3178, 'قلح', 'وفاء', NULL, NULL, 's8bfgkjg', '$2y$10$KK3Gaoi6wF./TDKDK0StHuY1Dg7vLHggwjygtXc4QnUJHtDKFDoSu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:15:01', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '54667094'),
(3179, 'التباسي', 'سلوى', NULL, NULL, '4nr1p3x8', '$2y$10$QX4HRuzZ5D268ZrVPAPrj.82bl.nG3W64OnsSqpFxM9FcIygPFAtG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:18', '40 DT', NULL, NULL, 'فوق 26', '97488162'),
(3180, 'حمزة', 'حنين', NULL, NULL, '736w753q', '$2y$10$lj2MvHEN58fgk8f8mco0c.RTKbu7KqDs2ImTz3RttvxNgzg9vznYa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:51', 'معفى', NULL, NULL, '13- 25', '25224848'),
(3181, 'حفصاوي', 'آمنة', NULL, NULL, '2sio9xwu', '$2y$10$lXEsQgNs2ueS4Luc0iD81uk00CrY7waoYnzN/1slei3JrAJcEOUzu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:51', '20 DT سداسي أول', NULL, NULL, '13- 25', '27721397'),
(3182, 'الماجري', 'ندى', NULL, NULL, 'z6u9t42k', '$2y$10$oAEv.bd.TiDlC91RRYcLJeX0fi5y7ffbHiaMokYU8jUg1/2Rm7vyq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:32', '20 DT سداسي أول', '1024046376', 'محمد الماجري', '6 - 8', '28983120'),
(3183, 'عرفاوي', 'عفاف', NULL, NULL, 'kpkjvt5v', '$2y$10$MiLsPKsssF9a2zwuifCJR.E3i6svv6aawWbyOX3zRjqFC80rxpgGe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:57', '40 DT', NULL, NULL, 'فوق 26', '55534222'),
(3184, 'القصير', 'آمال', NULL, NULL, 'rnzl5dq0', '$2y$10$qWz7tUTqDwm9fQiwAg7rmu1Cze4IXgx1Wd0t2HwrWd8JYWBVlXUCS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:31', '40 DT', NULL, NULL, 'فوق 26', '93048199'),
(3185, 'بن عبد الله', 'عائشة', NULL, NULL, 'c9tx503z', '$2y$10$KfQx6pPN2zvobYoIFyUCVOPSuFnlDeqczXPm0yE97wWjPr.cLj9o6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:42', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '26089961'),
(3186, 'الشتيوي', 'أمينة', NULL, NULL, 'igjdf8i8', '$2y$10$antau5xfVD9c7gC0x.8uLOVq.7l781HGH.iX5ror6W/HOz1B1FuqG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:24', '20 DT سداسي أول', NULL, NULL, '13- 25', '93938855'),
(3187, 'الشتيوي', 'فاطمة الزهراء', NULL, NULL, '98uqj2z0', '$2y$10$gEMpa1BhFCjpTeF8QIYDsujg4lSGvJr6nRUn3PwCGmV1rLUCJKKJK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:24', '20 DT سداسي أول', '1291329674', 'هادية براهم', '9 - 12/ 13-17 (للحالات الخاصة)', '93938855'),
(3188, 'قنواطة محجوب', 'آية', NULL, NULL, 'ha6nglyl', '$2y$10$78JGxarvvYRbZXKG3G3ASuverNEY7t0xKI05y2/9ie63GQAjTOT4C', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:15:02', '40 DT', NULL, NULL, '13- 25', '28723553'),
(3189, 'بوقديدة', 'راضية', NULL, NULL, 'tp97335n', '$2y$10$GaSNN1wmczke1kDiT/NfAODgUBTnJDtNacYa6BbMSKsu2kkUCr6KW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:45', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '97834492'),
(3190, 'بوقرن', 'فاطمة', NULL, NULL, '890qfrou', '$2y$10$d42BmbFNT4tzj9CPinPKuuzx393PEygU1B26.Tkz0qVshVCqEAz7q', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:13', '2026-02-28 21:14:45', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '28655152'),
(3191, 'عباس', 'محمد', NULL, NULL, '82viq3l1', '$2y$10$K3PFiBUKKCEiNwtBiyyEWuDVGBJakT9.3yXY35vIUO1j8cHDk6tFa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:56', '20 DT سداسي أول', NULL, NULL, '13- 25', '27730456'),
(3192, 'عباس', 'آدم', NULL, NULL, 'euxdiweb', '$2y$10$rH4w9i5DXraFgPZnMzoIcuoPslwV8YbxwMGXhkoXXYBF9vRxgoK1u', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:56', '20 DT سداسي أول', NULL, NULL, '13- 25', '27730456'),
(3193, 'الاكحل', 'تيسير', NULL, NULL, 'twouy7wz', '$2y$10$nrmZ./vENsk0iTRYuuHVi.ebFSWwCTjzqnFUf7VFzB5stvP4YLMZe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:16', '40 DT', '3409368124', 'فائق الاكحل', '9 - 12/ 13-17 (للحالات الخاصة)', '52775847'),
(3194, 'الاكحل', 'ياسر', NULL, NULL, 'a2fe3fkv', '$2y$10$r4GbTvv1wXPwBRTd8/gFx.Xqv6YN1/huFUcc35As5A2Epu9ZkGbae', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:16', '40 DT', '5153316269', 'فائق الاكحل', '9 - 12/ 13-17 (للحالات الخاصة)', '52775847'),
(3195, 'الرويس', 'عائشة', NULL, NULL, 'otsgzyyu', '$2y$10$P/4ET4FrKX8Vm1JLSjRBOOkBpq7YKzuvVv8VJ2rMv0RdLiNwOGq/a', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:21', '40 DT', NULL, NULL, '13- 25', '28470004'),
(3196, 'بن الاكحل', 'هناء', NULL, NULL, '9mnaze7k', '$2y$10$aaWiE9A3o3W.thEqbEus9.idWagzd5Dp.5ba1vqgYY46rwjAjZG32', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:37', '20 DT للعام الكامل', NULL, NULL, 'فوق 26', '28470004'),
(3197, 'الرويس', 'بدر', NULL, NULL, '08os86ex', '$2y$10$U/YPTX4SR9IZN1ycsPmRnelHUDo5x9opozgzUAPS2zpGjUCXxhzqu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:21', 'معفى', '3169730836', 'حسن الرويس', '6 - 8', '28470004'),
(3198, 'الرويس', 'عليا', NULL, NULL, '1u1wlskw', '$2y$10$tNt4PIOSEzNWP8OqKIG.KuOMxRwx7vDEcdOtZl8cd694S2ZyqaQmu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:22', 'معفى', NULL, NULL, '13- 25', '28470004'),
(3199, 'القارص', 'أسامة', NULL, NULL, 'k24eagfb', '$2y$10$deODJ7HgaYKw6rbNzCCxbugN5xfDArA9491Smu7NGcQ9nBoiqcIkG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:29', '40 DT', NULL, NULL, '13- 25', '98640370'),
(3200, 'القارص', 'أيوب', NULL, NULL, 'mlmeuqst', '$2y$10$Wdh7i0TG/oMNsqQhEvhsf.zczOlkaiejkSpurdQDhaIEaaCAvtSvO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:30', '40 DT', NULL, NULL, '13- 25', '53680370'),
(3201, 'القارص', 'آمنة', NULL, NULL, 'b394x7br', '$2y$10$1yzijGhjVUOqxLyzVwFnBuoGc9vmilXnObhDBc4DKmpSFYFcyHriW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:29', '20 DT للعام الكامل', NULL, NULL, '13- 25', '98640370'),
(3202, 'بوهلال', 'ملاك', NULL, NULL, 'f81vzpzj', '$2y$10$ogsdbnUP5yRDyaQVQwPOGeYSa8lx2MPFTpIkDmG543ZM3yq5awQTa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:48', '40 DT', '1094911710', 'محمد بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '23756788');
INSERT INTO `students` (`student_id`, `last_name`, `first_name`, `middle_name`, `name_suffix`, `username`, `password`, `last_login`, `failed_login`, `custom_200000000`, `custom_200000003`, `custom_200000004`, `custom_200000005`, `custom_200000006`, `custom_200000007`, `custom_200000008`, `custom_200000009`, `custom_200000010`, `custom_200000011`, `created_at`, `updated_at`, `custom_200000012`, `custom_200000013`, `custom_200000014`, `custom_200000015`, `custom_200000016`) VALUES
(3203, 'بوهلال', 'ملكة', NULL, NULL, 'd81js4wb', '$2y$10$5bZI91wtTp39.m5LxL7sdurSFXXeY7C.cYZIH0vsYysCAfdl/mAUa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:48', '40 DT', '4285000965', 'محمد بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '23756788'),
(3204, 'عجرود', 'ملاك', NULL, NULL, '1qc5aypy', '$2y$10$Z.HipHfwF42aAUB/mJo1A.U8lTwnGkQ3UhuSSoBFI77G3EDDIdSKe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:57', '20 DT سداسي أول', '8905879386', 'مهدي عجرود', '6 - 8', '53276319'),
(3205, 'عجرود', 'يقين', NULL, NULL, 'h4e4xds8', '$2y$10$DJpC.8xz7oTL/LZ9z00aPutXofuch2GJi9YIAVD8Iwqvkljc2SvwK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:57', '20 DT سداسي أول', '3513125182', 'مهدي عجرود', '9 - 12/ 13-17 (للحالات الخاصة)', '53276319'),
(3206, 'بوهلال', 'محمد ياسين', NULL, NULL, '6q57yzrc', '$2y$10$adrtm/qR.XSYoiL5pULz3.7C.OZq4NKBwukhpV6P9q.zCqebnMeLO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:47', '40 DT', '4615663962', 'عز الدين بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '98202414'),
(3207, 'بوهلال', 'ابراهيم', NULL, NULL, 'wj2zcr9t', '$2y$10$UW4AKMPp04xYlhnWWBer3u7txw/ghnncYt3FksyJpGve5KrIAvM4u', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:46', '40 DT', '8002195559', 'عز الدين بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '98202414'),
(3208, 'بوهلال', 'مريم', NULL, NULL, 'chlmrnns', '$2y$10$/DrhHzV0rwvMmk7jEDoaGeCymjVF1te2d0MY5z4.HjIzIGU21bD8e', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:48', '20 DT للعام الكامل', '8622756392', 'عز الدين بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '98202414'),
(3209, 'العزيبي', 'ياسمين', NULL, NULL, 'ibcvyrvr', '$2y$10$EMOZpW3Mvej94OHs8MWPYOxh.zgwWzlEDScK/BrakO8cKNs0tyANG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:27', '20 DT سداسي أول', '7425874022', 'سالم العزيبي', '9 - 12/ 13-17 (للحالات الخاصة)', '23125991'),
(3210, 'التواتي', 'تقوى', NULL, NULL, 't3tdz8nr', '$2y$10$TgRvFYeD0OH5U4omVvlyyutUY8DmBkDLqLX1MylqE42E0aPH41qFC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:19', '40 DT', NULL, NULL, 'فوق 26', '52775847'),
(3211, 'بنعلي', 'شهد', NULL, NULL, 'dkgogfnu', '$2y$10$YN2ENkQENLIMqnlPYdLGAOwesp9hI4vq.KAy4VxHfmZHSuT11dJ9a', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:43', '20 DT سداسي أول', '9983300927', 'صفاء بالحاج الصغير', '9 - 12/ 13-17 (للحالات الخاصة)', '99129461'),
(3212, 'ابن الحاج الصغير', 'صفاء', NULL, NULL, '87nlklo9', '$2y$10$VpRF1R5i5Tms8W/DCQgeNuQ6VU4HDWJKd8HndD63uduj/A9tmZcfi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:14', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '99129461'),
(3213, 'بن سيك علي', 'سناء', NULL, NULL, 'n2g5xo4q', '$2y$10$nbD1PxngxyjzknDgcD33R.lmRg5LdP/2t8RWkMWMMjZfzB.8A2XZy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:40', 'معفى', NULL, NULL, 'فوق 26', '26543704'),
(3214, 'بوتيته', 'إيمان', NULL, NULL, 'a0oq8vye', '$2y$10$YLyKsU4Q6rd/0xFEcuXH.OM7srqASwAKleIzi.gUA.6VPOUoptd/m', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:43', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '25083399'),
(3215, 'شعابي', 'عبد الله', NULL, NULL, 'u6dx6t00', '$2y$10$6r2ecQgWkWb6MfOEkf95LOpGvuvRL8wxteQsbBlMGAtjXLHeNkCru', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:55', '20 DT سداسي أول', '.', 'فيصل شعابي', '9 - 12/ 13-17 (للحالات الخاصة)', '25083399'),
(3216, 'بن ابراهيم', 'اسامة', NULL, NULL, 'm5hrnx4n', '$2y$10$3QQrJK6PzQaEHWfw7RUjDeGMafxPYB5NXORJLsukOjiWnmD21hvf.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:37', '40 DT', '4772632392', 'محمد العادل بن ابراهم', '9 - 12/ 13-17 (للحالات الخاصة)', '22953270'),
(3217, 'القاضي', 'آمنة', NULL, NULL, 'pbztyxxx', '$2y$10$vrjPq/Nvd7FsBm/Wc85BcuS2g6Hs3CvpdhAqnMrc5Vz9WxvaK8gS.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:30', '40 DT', '5534752096', 'سامي القاضي', '9 - 12/ 13-17 (للحالات الخاصة)', '21029310'),
(3218, 'البزيوش', 'سنية', NULL, NULL, 'k66ghenp', '$2y$10$47.RxxM8AmQz0EGfa8J7luP3KROyBrcwURNKF.FN28WYuHIbqgZGC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:17', '40 DT', NULL, NULL, 'فوق 26', '22946100'),
(3219, 'المجدوب', 'ملاك', NULL, NULL, 'za9x70oe', '$2y$10$iP5xA2NV3PmxDODYupRHSOEjC1ysfwp8iGpfS.Zx25X8oiFm7hQeW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:32', '40 DT', NULL, NULL, '13- 25', '20661528'),
(3220, 'المجدوب', 'آدم', NULL, NULL, '4v933hiv', '$2y$10$jZpVtgYvRnrRHWwRT6cUPeyluuom6Ovbf8MPeQywcWJKCY6J/YD0S', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:32', '20 DT للعام الكامل', NULL, NULL, '13- 25', '.'),
(3221, 'المجدوب', 'يحيى', NULL, NULL, 'eomfsdrq', '$2y$10$l/Jau6C6xV126k.UNTHvMONKvpH8DfkmXxueNJlp3zAfBHFyN0DJy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:33', 'معفى', NULL, NULL, '13- 25', '.'),
(3222, 'تريعة', 'محمد أشرف', NULL, NULL, 'awk3p9ro', '$2y$10$xtuQ40iEzEDOxZcSJ8owYOf4vlgmRaQrI.6nBg.wtLY.yfoyr7Aa2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:49', '40 DT', NULL, NULL, 'فوق 26', '+216 24 845 211'),
(3223, 'هميلة', 'تيماء', NULL, NULL, 'ssfszjxv', '$2y$10$4HoL7r.ubb7.2TzyRqyTUujhCgHuwPSsnuz4Zy95gPO7Fv.ag21j.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:15:06', '40 DT', '3477179511', 'مروان هميلة', '9 - 12/ 13-17 (للحالات الخاصة)', '26250506'),
(3224, 'بن البحار', 'حليمة', NULL, NULL, '5invmnbg', '$2y$10$Rp3KETki/a0qHG4slj6NMuBgMk6qJAFEVTFo3iq0PTzyjcMmgIx12', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:37', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '99764443'),
(3225, 'التوتيتي', 'ألفة', NULL, NULL, 'e01oj0hm', '$2y$10$7LLokezWMQPt4kFfbzGN3.lY8ktunSbNIGg6UEAKoYhvxKxkHPA4.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:19', '40 DT', NULL, NULL, 'فوق 26', '20324344'),
(3226, 'بورورو', 'ابتسام', NULL, NULL, 'yy4oxsz4', '$2y$10$fzUvyjWxd5oTaB8vLxrwfuNs50fbklFVjwENIVLhypncS4f0kg7M6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:43', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '92929478'),
(3227, 'قشة', 'نعيمة', NULL, NULL, 'yvrhpvej', '$2y$10$c/rUTp0MPAF4AloaIB4WTe0Wyn5gyaB6b/ofweKIwtEhbIfGF2ghG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:15:00', '40 DT', NULL, NULL, 'فوق 26', '54716548'),
(3228, 'الغماري', 'فاطمة', NULL, NULL, 'jkazwjcz', '$2y$10$GwLnoNJ5MIQMXqUrp58zl.fzGmRzE4K9tECvd7jrZPqgx0Ma/rW4W', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:29', '40 DT', NULL, NULL, 'فوق 26', '97847569'),
(3229, 'القصير', 'بثينة', NULL, NULL, 'mj18bt7m', '$2y$10$TCbVwMJ9pMO7obPFLn89Zum3wSUR1XYVnAXq9QeyEDp6xxBOytUam', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:14', '2026-02-28 21:14:31', '40 DT', NULL, NULL, 'فوق 26', '50300392'),
(3230, 'بوريقة', 'خالد', NULL, NULL, 'sd9hc6o7', '$2y$10$MDJ481b.iCM2bSrHY7kL.uNim2T6LT2qNaqoJGHsbCxRbkKBXOgyS', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:44', '40 DT', '8132338641', 'خالد بوريقة', '9 - 12/ 13-17 (للحالات الخاصة)', '54008833'),
(3231, 'الغماري', 'منيرة', NULL, NULL, 'kvwuy5m7', '$2y$10$Ol6SAf34HzbVmv8vzSzgGeg18C50JhcofuuPwXGHYAvTlFXNgIZ2.', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:29', '40 DT', NULL, NULL, 'فوق 26', '52066710'),
(3232, 'بوهلال', 'الهادي', NULL, NULL, 'qmm33qfm', '$2y$10$owp0yMxNAOcEmcWgzXuNh.gWBazObXqAls6xd7g3bZfF.o7Pf0wyu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:46', '40 DT', NULL, NULL, 'فوق 26', '97311396'),
(3233, 'حواس', 'محمد ريان', NULL, NULL, '10wy7x86', '$2y$10$k2Sj0ZTSgX/61Qg744Wh0.IMR2wPiZKjbwuBGb6gh3vvqMf2KkSGG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:52', '40 DT', NULL, NULL, '13- 25', '.'),
(3234, 'قعيب', 'يحيى', NULL, NULL, 'cyy6ha56', '$2y$10$D5ElLrmpRxWugDBaGIuveetdbwFJKyxH6E8NCUbCbH01WHByHoxm6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:15:00', '20 DT سداسي أول', NULL, NULL, '13- 25', '97225100'),
(3235, 'الزرقاطي', 'معتز', NULL, NULL, 'ibuogg2s', '$2y$10$ksqPmqYlLaewIz09CMHl6.iFFttHkX7h5O3UpIWovIYIqs0J62LKi', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:22', '20 DT سداسي أول', '1030226560', 'كمال الزرقاطي', '9 - 12/ 13-17 (للحالات الخاصة)', '96241088'),
(3236, 'البكوش', 'إسراء', NULL, NULL, '26g92hqe', '$2y$10$o6wbRsGNrttCEZwEt9zUzOz4Vc3Xn2OWHwcIaTdNxBTs/oqVITEtm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:18', '20 DT سداسي أول', '9257463691', 'لطفي البكوش', '9 - 12/ 13-17 (للحالات الخاصة)', '58498855'),
(3237, 'بوهلال', 'زينب', NULL, NULL, 'firl5et0', '$2y$10$8E/bkAARul72HorNea0VTeccxyul1pSP6OQyxKQ.RTeit3OBioMui', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:46', '20 DT سداسي أول', '.', 'الصحبي بوهلال', '9 - 12/ 13-17 (للحالات الخاصة)', '55043105'),
(3238, 'عزيز', 'حليمة', NULL, NULL, 's8znbpiv', '$2y$10$n9cjjPDG/4vlbr7Qxoj53Ous2RAfURkwg6HeBy68diphRBFwz/qQW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:57', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '24838651'),
(3239, 'عجرود', 'يارا', NULL, NULL, 'ky9zomrw', '$2y$10$QH3F6ZM9WeMjuuKb/NCdPOwtBLYzCsmRLmaLtUcHjNAQV4YISHUoi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:57', '10 DT', '3794366578', 'ناجح عجرود', '9 - 12/ 13-17 (للحالات الخاصة)', '24838651'),
(3240, 'رويس', 'سليمان', NULL, NULL, 'nqe9i39n', '$2y$10$Re3friRq0gOJaGTCLph9B.BTk9H1tajDZ4EpZJVzvfFXiTkZrSy0K', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:53', '40 DT', '1104962118', 'محمد العربي رويس', '9 - 12/ 13-17 (للحالات الخاصة)', '50531570'),
(3241, 'شويخة', 'مريم', NULL, NULL, 'agu0ramr', '$2y$10$f.5mN3Cwk/JYvaJYF2gUX.oD1P9TWmeWtE9bvVahCfROV4HKXLgre', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:55', '40 DT', NULL, NULL, 'فوق 26', '50531570'),
(3242, 'جرار', 'فادي', NULL, NULL, '1wf8ihah', '$2y$10$uvb2FsFXORNkgGnMA8kdnuS9xEnCr7oP8cPYJeov45dwLR0sR7xPm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:50', '20 DT سداسي أول', '.', 'سنا المجدوب', '9 - 12/ 13-17 (للحالات الخاصة)', '28886326'),
(3243, 'المجدوب', 'سنية', NULL, NULL, '4rywpl9b', '$2y$10$RNlWdkYR4xvowlFEpWhDZ.Zk9JzEgD.CwRqEs06bpkodrJd9y/6QG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:32', '40 DT', NULL, NULL, 'فوق 26', '50335892'),
(3244, 'السافي', 'عقيلة', NULL, NULL, 'hsfawg0f', '$2y$10$9QnOgztz2C5xOScOsVbyJuQHbCVUN6idtE8Pv/fq6/f0d4SGAFN2S', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:23', '40 DT', NULL, NULL, 'فوق 26', '99870000'),
(3245, 'قلولو', 'هدى', NULL, NULL, 'it95p1qh', '$2y$10$8bsCQU9DzJVKhK7WN7RS2uJjq6qSZzcuRRRHH1fZizAVPZFSnaCGe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:15:01', '40 DT', NULL, NULL, 'فوق 26', '22098105'),
(3246, 'قلولو', 'ايمان', NULL, NULL, '4unmhatx', '$2y$10$TH2YXc3U/p2KAqvkTS8K2Od7lS3CV93jst2XLwOHk1vJFh9AeTMA2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:15:01', '40 DT', NULL, NULL, 'فوق 26', '22098104'),
(3247, 'عطية', 'زينب', NULL, NULL, '2qzl20bt', '$2y$10$HiErCHDyTf1WOteK.DaxzuM1MdAOTtAA17niVmL4nqCrAA44uXSxq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:57', '20 DT للعام الكامل', NULL, NULL, '13- 25', '28825882'),
(3248, 'بن خليفة', 'محمد', NULL, NULL, 'bpsfo18v', '$2y$10$mme9HDsW8r.abA7ZG16AieFxgm/6QrJs0w2rSYtWjdXEeYf3lcPDu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:39', '40 DT', NULL, NULL, '13- 25', '98456843'),
(3249, 'ابن الحاج خليفة', 'محمد زيد', NULL, NULL, 'm16wlhnz', '$2y$10$o3YmF4W1qx9wNLd4tXTeVuxntsYd5XLRGNB5z60ngUQzbvCPv0E1m', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:14', '20 DT سداسي أول', '3709457832', 'حنان بن حمودة', '6 - 8', '93653005'),
(3250, 'القابسي', 'زكرياء', NULL, NULL, 's02l26je', '$2y$10$t4fmjNsxLu.sP1lghlyrc.ZVuPfKNJJikcBQTX/ZdyVOoCgwO0Ee.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:29', '20 DT سداسي أول', '5194302611', 'منير القابسي', '6 - 8', '96228709'),
(3251, 'بن عبد الجليل', 'زينب', NULL, NULL, 'u1l1w2nk', '$2y$10$nQAqtvJsowyKIhZ5qBo6N.ZVMO.AnP3jNOXwJnrhd/UDZ3aUqajXu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:41', '20 DT سداسي أول', '5547830528', 'طارق بن عبد الجليل', '9 - 12/ 13-17 (للحالات الخاصة)', '56144349'),
(3252, 'بن عبد الجليل', 'سلمى', NULL, NULL, '48xhy2wk', '$2y$10$yjZCdmISbw0uTF9sMDdICO/vbABMGBKNZIW9dtzqkHH2xPgXqxTbm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:41', '20 DT سداسي أول', '2935410259', 'طارق بن عبد الجليل', '6 - 8', '56144349'),
(3253, 'بن عثمان', 'زهرة', NULL, NULL, 'w3njc5pq', '$2y$10$A3nL.6wHL9DA1L/GFDBqqO2nNRSViFY5oy/vdpbfhcGhecVTKMk0a', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:42', '40 DT', NULL, NULL, 'فوق 26', '54990285'),
(3254, 'بن عثمان', 'حبيبة', NULL, NULL, 'ndmvystr', '$2y$10$0m7VtIkz7RmFTl0rByEctO6ICLvZsK8sjL5mV63m/6uaIYzfRLsmm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:42', 'معفى', NULL, NULL, 'فوق 26', '97847181'),
(3255, 'فطحلي', 'عربية', NULL, NULL, 'ms7sjgis', '$2y$10$Njg4N2ITL.h5c0y8GRD4BeK/UcTSMYizFj.cTeTc70Z342LbihBsi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:59', '40 DT', NULL, NULL, 'فوق 26', '29550779'),
(3256, 'قرشان', 'نجلة', NULL, NULL, 'etdly2ya', '$2y$10$/.Ilf.lxhJktrnjVlApNCOGwTCOR4NJ40nzSH6kHVLdT3i/FHG4bK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:59', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '52808005'),
(3257, 'المليح', 'سندس', NULL, NULL, 'k0rgxclj', '$2y$10$I3asgrP6PHOFrjNNMMkHnuKupHZ7zWYD24apcBbH6HfwxifDPYEBq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:33', '40 DT', NULL, NULL, 'فوق 26', '.'),
(3258, 'كريفة', 'هالة', NULL, NULL, '22ulv4x8', '$2y$10$osTToDmhx9M40quGujaKWusgPspxnxVt6C4PMD9ibHbk7ILBnTZQm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:15:03', '40 DT', NULL, NULL, 'فوق 26', '96604222'),
(3259, 'المشرقي', 'ذكرى', NULL, NULL, 'yty5enfi', '$2y$10$u5QDCPPK6VxwlZ0b1ohl1OiMnOxljh2Dj6OPgieOT9952oeqc/gHm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:33', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '56028917'),
(3260, 'القزاح', 'اياد', NULL, NULL, 'onjknqnm', '$2y$10$i7NvR7uqT2TCOeWANLCE0u3fm.5WlyI0.70raHu60doH3lo.aC1d2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:31', '40 DT', NULL, NULL, '13- 25', '98608183'),
(3261, 'بالعربية', 'اسماعيل', NULL, NULL, 'ofdk5dby', '$2y$10$oY/RCvwgWy3khdHRb6TKMO6LAwqCj8iwW51uaO0Uy.Spoc2TRjkG.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:35', '40 DT', NULL, NULL, '13- 25', '23013356'),
(3262, 'بوهلال', 'مروان', NULL, NULL, 'gho7f0l8', '$2y$10$VZrggLXbuxYPlGtSo4wh6e.i4WgjCEbBVF1TAfpOtOgqE9a/4qoNy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:48', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '.'),
(3263, 'الأندلسي', 'الياس', NULL, NULL, 'aw4ldef7', '$2y$10$UXxR4vgBggnX.YeyMfPcm.QaLTg.zgWCz1Z4tv77FuUCZnzD8f/bW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:16', '40 DT', NULL, NULL, 'فوق 26', '93426402'),
(3264, 'بن خليفة', 'ايمان', NULL, NULL, 'r05j99ba', '$2y$10$PWJobdvvUTYXFXTj5VSMRes1UCxdCnKgeS3MHHt1VXLhpD2GfA2Le', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:39', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '58898323'),
(3265, 'القزاح', 'هارون', NULL, NULL, 'yhe677m7', '$2y$10$VH.phslsHrh5R9nmrILLGeIkeYzVxOYto5kfPrb7BM/q8HHj7vsfK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:31', '40 DT', '.', 'أماني قزقز', '6 - 8', '98608183'),
(3266, 'الناقوري', 'نادية', NULL, NULL, 'ej7gvuyn', '$2y$10$hQ5kT6a6xrhqmW7aGBp78uZrAwNpqnqI6yStCd0ZwwsJ6WkS1vcCm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:34', '40 DT', NULL, NULL, 'فوق 26', '52277988'),
(3267, 'عمار', 'سجود', NULL, NULL, '6fup0s3y', '$2y$10$uFTSbbkqHuQt9kjHwsSbRuf/MBqJIYXZppix5oK8Sv5QZimlXVx96', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:15', '2026-02-28 21:14:58', '20 DT سداسي أول', '2169787138', 'أنيس عمار', '6 - 8', '21112749'),
(3268, 'ابن عبد الله', 'سيف الدين', NULL, NULL, 'hx3118dl', '$2y$10$jXIaOux/OD2gDI39Gu9b1eDgCQFQL5P/sK1JqdusZbyyjihzpFOh2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:15', '40 DT', NULL, NULL, 'فوق 26', '.'),
(3269, 'سعدانة', 'رحمة', NULL, NULL, 'pi68l9gc', '$2y$10$a2WbxovtjvTV1DdRPHU0wOj0shIlxWi4tCrdn8ZltxdVwkjiFLfpi', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:55', '20 DT سداسي أول', NULL, NULL, '13- 25', '23917974'),
(3270, 'سالمي', 'اية', NULL, NULL, 'he293xfp', '$2y$10$fCBU81IrgFzZdKkkyjPrUehKQVdlpN81tQMWSiUncI.2PPPz/wpvO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:54', '20 DT سداسي أول', NULL, NULL, '13- 25', '.'),
(3271, 'ابن الحاج الصغير', 'نوفل', NULL, NULL, 'vfdigclc', '$2y$10$st2uoGNcf6/Hr7NfSOjdl.k6jR75cwGXRyqan97XE7jbIQ1h9qeEO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:14', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '40298843'),
(3272, 'المخنيني', 'محمد صالح', NULL, NULL, '54fpw3e0', '$2y$10$aCXBmaPoUE8Tx1iC79eyQuLW1H.XOsabq1icd36JJy/N0kCRAicKC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:33', '20 DT سداسي أول', '8678198057', 'نزار المخنيني', '9 - 12/ 13-17 (للحالات الخاصة)', '58387261'),
(3273, 'الغربي', 'محمد فاروق', NULL, NULL, 'tuggb7fh', '$2y$10$TnfQyJBXj1bnITZythOvm.ceVEWbPjs2.C/.i2gyxDepo.XnUkbL2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:28', '40 DT', '2734832548', 'محمد زبير الغربي', '9 - 12/ 13-17 (للحالات الخاصة)', '21221890'),
(3274, 'الغربي', 'محمد ياسن', NULL, NULL, 'am9byroc', '$2y$10$FZLzWabxPi5KATKhAXKA0OKEB50l41Mjrhx2sWCQ4Old6Rt94eOn2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:28', '40 DT', '4890605210', 'محمد زبير الغربي', '9 - 12/ 13-17 (للحالات الخاصة)', '21221890'),
(3275, 'تريعة', 'ليلى', NULL, NULL, '0wqfpafz', '$2y$10$GzEBs0qTvb/qSCTS.o/6J.OYajWVormz6.y4/nRziWDR775bxgwwy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:49', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '28304950'),
(3276, 'الغماري', 'سامية', NULL, NULL, 'd43bo1or', '$2y$10$HpLu6EZbz.SwIGwtKUckAOPfqaf4hQSS7iKP9ptiA/sSgjRS5akLK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:28', '40 DT', NULL, NULL, 'فوق 26', '96441103'),
(3277, 'الدهمول', 'محمد', NULL, NULL, '0eb37llx', '$2y$10$BIdyEZNj71Xy1savdatSHuevttoO/BqNgNKkej2gsubvbB/YdEO6.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:21', '20 DT سداسي أول', NULL, NULL, '13- 25', '53279449'),
(3278, 'بن عثمان', 'رحاب', NULL, NULL, 'd64ezfp4', '$2y$10$7xRMjNvogIraZ0WF0fQZku63RGjISeBayRMhMCm6YqT/1uoj6QXcm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:42', '40 DT', NULL, NULL, '13- 25', '26837974'),
(3279, 'الخلوي', 'وفاء', NULL, NULL, '9zlvksid', '$2y$10$kKBQoqgbjdqvewxY1Z6JW.wrAzZOVoNXn06lKf4ouCwnbwXV37AwC', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:20', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '20887999'),
(3280, 'دودو', 'وئام', NULL, NULL, '8z7yrb9j', '$2y$10$9HVdZxxQtRNz5QRROTJa3.oZ9VToLjdcquJlRwkpTdXgC55WV3ori', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:52', '40 DT', NULL, NULL, 'فوق 26', '29664780'),
(3281, 'الضيف', 'ناضم', NULL, NULL, 'nnuabg09', '$2y$10$sHEsvCsGLwESIbWaRHpB/uW.NA2es2nBFOJ2grPggogKNi/B2hO1u', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:26', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '52528330'),
(3282, 'شعرانة', 'مروى', NULL, NULL, 'ruwipvyf', '$2y$10$c0Mcj8a01E.QkrFYs9S65uX2dAA.EFToEsSileKLbOTYmsdfliwyK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:55', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '25240082'),
(3283, 'بن العربية', 'نورز', NULL, NULL, '9a2obvp2', '$2y$10$taD6SDZp4wOsoyebpa8Vlunwxi15JUkI/JOmyBWzq2kiSYkp/dfTe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:37', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '24603621'),
(3284, 'الرقيق', 'منال', NULL, NULL, 'wjccn4zf', '$2y$10$k7z1AgzAfW8uYoa2bcT9UOE3mYQxmGnmhamoyp/Fm5eeB2AM3CCpO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:21', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '.'),
(3285, 'هميلة', 'ياسين', NULL, NULL, '7nwwtkoa', '$2y$10$lCaZREOEsET15d02dsFIWOheocqFJWSLE2ZaMPUivPM//16lASk2O', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:15:08', '40 DT', NULL, NULL, 'فوق 26', '29675013'),
(3286, 'بن حمودة', 'أنس', NULL, NULL, 'jfxde9y1', '$2y$10$iNml3Tl109Wl5exL6Yn/hOC8bDB4LYsiKRqSqmeAzEwwwTWrfXYh6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:38', '40 DT', NULL, NULL, '13- 25', '56772502'),
(3287, 'بوناب', 'بلال', NULL, NULL, 'tmlwbuf2', '$2y$10$idn0QbERPlXyuDI4FhmQPOOgiaypG8hhDhmSqUoDYzrNX/YTaYp..', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:45', '20 DT سداسي أول', '3922309780', 'وداد الشطي', '9 - 12/ 13-17 (للحالات الخاصة)', '95719956'),
(3288, 'هميلة', 'شيماء', NULL, NULL, 'kvoxrjcr', '$2y$10$5W35Lu7RnwyxJ7EjcmYnce9FkSfJ9cuQnZu1HL3VOu.wpISAe/3lG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:15:07', '40 DT', NULL, NULL, '13- 25', '52252533'),
(3289, 'دحين الشطي', 'أشرف', NULL, NULL, 'bxv2r61s', '$2y$10$Qk5tWY7kof/E9cgFkn6A/OH.imr/ZoJaIdwMzfWlG6VCt.x1JW4yu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:52', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '58939800'),
(3290, 'انقزو', 'ماجدة', NULL, NULL, '13seuk70', '$2y$10$Kuc.d34tI6d3f6xg4SVlpu5RL19zZzs/8HhoPrueD0NF6boNtKru6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:35', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '50206162'),
(3291, 'ساسي', 'ريان', NULL, NULL, 'qfkqtp2h', '$2y$10$NeF59YwsYyNKGIyvodjx1O2S6u.jI1FyG.GMWfw09tok1Z1Zm/ave', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:54', '20 DT سداسي أول', NULL, NULL, '13- 25', '.'),
(3292, 'المجدوب', 'ابرهيم', NULL, NULL, 'eilkiegw', '$2y$10$R8b5oM2agX7FqW5hBXhm3OQ3ae4Pch4q9uUMB5pnZn0KPWePaRGaq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:32', '40 DT', '2853332372', 'حاتم المجدوب', '6 - 8', '55786360'),
(3293, 'بوعصيدة', 'محمد يحيى', NULL, NULL, 'yii5rr3r', '$2y$10$LXJYdySr95pcjW0JrpLbfe/4Uy9sNijjQyuBHWHKdX2vasuXbxJ5y', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:45', '40 DT', NULL, NULL, '13- 25', '53834405'),
(3294, 'فريضي', 'الحسني', NULL, NULL, 'uus696fu', '$2y$10$FhEMsOISMddwejKFDf9qKugWejoZW8z.L//uS6rbUL2YfEbFVEgcu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:59', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '54863088'),
(3295, 'كشاط', 'وحيدة', NULL, NULL, '12qus91u', '$2y$10$MvL.K3XrGw/9AiyaFvaQtuuU/HIf5C95tVrMlnAA51qnzFto.rPBm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:15:03', '40 DT', NULL, NULL, 'فوق 26', '94819887'),
(3296, 'العشاش', 'وداد', NULL, NULL, 'kef6gjzh', '$2y$10$OtEryfqlR6TqLItonQtHc.8KoYLxXNT/9v4C3921DOnb7Fd9a4EVa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:27', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '22432715'),
(3297, 'القزاح', 'سعاد', NULL, NULL, 'f8uyitm8', '$2y$10$DSPkKaiHXYZeY.B56ybkPuaIX8FdJgOqYkq2G8YM/Ve4U0LeYZNXm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:31', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '.'),
(3298, 'القزاح', 'فوزية', NULL, NULL, 'r1i6xpn6', '$2y$10$WcbWzM9YrGTHF3sMcNYhm.y4zk1PRtac.2/S8zXqoKOZC0yuRyfNe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:31', '40 DT', NULL, NULL, 'فوق 26', '95729560'),
(3299, 'محجوب', 'هدى', NULL, NULL, 'uxto5ca4', '$2y$10$0oKIQmSA.seMRMqwzeGozuUHZuGp.sAVQ5fXFu4g7Ejl4Dbb5w67e', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:15:04', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '.'),
(3300, 'ابن عثمان', 'روضة', NULL, NULL, '3luntbxx', '$2y$10$V.Cd0j/iLlXlBt85I8Wc0.PVtvN.Xa/gsv5oVCxwUS83gr6X1jgbO', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:15', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '98983197'),
(3301, 'مصدق', 'نادرة', NULL, NULL, 'rnhky4qe', '$2y$10$ClXkJy/ddD.zGJRd2ro3SudUpBfj/EKUi16LywovPsQ4z1vetn7bq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:15:05', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '96570571'),
(3302, 'البزيوش', 'نادرة', NULL, NULL, 'b7w0pfkk', '$2y$10$WI17FXSSNhQQLFjp/QEhXu8Y2tNgA4p8muZqP4j3PKRjBEF36ojze', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:18', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '21761041'),
(3303, 'قفصي', 'بية', NULL, NULL, 's99uq6ft', '$2y$10$YJv9zm7hOsbmJdNDvOAEr.FZ5z2fs.qr4.LBVVRJWP6VxQJEJXSay', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:15:01', '40 DT', NULL, NULL, 'فوق 26', '20730676'),
(3304, 'نوير', 'وحيدة', NULL, NULL, '8y3n1yyr', '$2y$10$LeLI6Pot4kcUwNXp3xv/WuWP0Rgw5T4y1SzyW71pC/WF1sUY985AS', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:15:06', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '27850852'),
(3305, 'حكيم', 'حمزة', NULL, NULL, '5208mbqj', '$2y$10$4Q1yp1xyADNBLB9WfTVugew1F.iZczOFtH38w2Bcj2MZG4YlrunIu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:51', '40 DT', NULL, NULL, 'فوق 26', '97225614'),
(3306, 'حمزة', 'حيدر', NULL, NULL, '9krvxxfi', '$2y$10$4HeoEEpB.dSIRs5jqaCJAenjiSObrmvuXBSnpaczA1wdHN3P8.goK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:51', '20 DT للعام الكامل', NULL, NULL, '13- 25', '97225614'),
(3307, 'الرويس', 'حسن', NULL, NULL, 'b31drc5m', '$2y$10$wiU3cw0McPEqrN7/MGTd.exX092OMaTNalsbCyJhQX0ReE7.LAQBK', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:16', '2026-02-28 21:14:21', '40 DT', NULL, NULL, 'فوق 26', '26470009'),
(3308, 'الخشين', 'ابراهيم', NULL, NULL, '77ud3u4s', '$2y$10$m06cPdHIgiukMqPfKqrcRe8RMD4PqDiyCoSbSZMks8snnZXLWwv.y', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:20', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '98402660'),
(3309, 'تريعة', 'محمود', NULL, NULL, 'ndav2w8l', '$2y$10$/vKKOnmV2g3MYinYv6iZsOW9E3nFZeNtQFRMQvVXNSesqEJH0eWUG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:49', 'معفى', NULL, NULL, 'فوق 26', '53847126'),
(3310, 'الشطي', 'وسيلة', NULL, NULL, 'u33yo641', '$2y$10$Qfq6KDxOpwZQb7UHRaq8WuPRLXpFL3/Ojd/ogk9yotpjtQ7zuh9zG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:25', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '53567770'),
(3311, 'الشطي', 'وداد', NULL, NULL, 'z4gs32ij', '$2y$10$0iM.2s8Eg2.bWonBDkwgO.Y5iHL/s2nhJpzv08xMd.hRek73pVMNG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:25', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '95719956'),
(3312, 'قم', 'محمد ياسين', NULL, NULL, '63zpzbrc', '$2y$10$.KZN.dXz5q4..tlUaj.oLuSazM0jgQaXqOd4pTlPiU4LCtEQSI2Tq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:02', '20 DT سداسي أول', NULL, NULL, '13- 25', '98480937'),
(3313, 'بن خليفة', 'حمزة', NULL, NULL, '9i7rzase', '$2y$10$7P72BjvsFL.aM/2tjcl5ceX8VRlcHCWZyEsPKWOnE6tzypM8nNYd2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:39', '20 DT سداسي أول', NULL, NULL, '13- 25', '29519591'),
(3314, 'اللجمي', 'إلياس', NULL, NULL, 'ao8pdyaf', '$2y$10$L/zB/4lHTSACE5rPoYnQduipNe/PtwgxzB1CT0O9s.BNCBQWR60U6', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:32', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '29488700'),
(3315, 'فائدي', 'عفوة', NULL, NULL, 'isg1v6r3', '$2y$10$bCNxuoZL5iic2VWiWDObruqxCqwz64oOEzTSwRwUmkiiXsJDsD2AK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:59', '20 DT سداسي أول', NULL, NULL, 'فوق 26', '56574184'),
(3316, 'مريزق', 'أدم', NULL, NULL, '9tsoqf0g', '$2y$10$u16gz.ajalJKb8EkpiL6F.Wo7NelgLHPSbGhRU0nO8NHw/ncqJQ/.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:04', '40 DT', '9017150413', 'إيمان قراصة', '9 - 12/ 13-17 (للحالات الخاصة)', '50618982'),
(3317, 'هميلة', 'نجاة', NULL, NULL, '7h2ouz60', '$2y$10$maM2x3AYakcTxPrHR3RidOW85kWeWRJfozU9c.fMXeuWij9buSYI2', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:07', '40 DT', NULL, NULL, 'فوق 26', '29208822'),
(3318, 'بن عزيزة', 'عبد الحميد', NULL, NULL, 're8or56y', '$2y$10$rgMd6qH20Y5GZzFNXTz44O1GcGCMPcJsMsAq72Woqp/HxYY/4bRUG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:43', '20 DT سداسي أول', '9514497806', 'نزيه بن عزيزة', '6 - 8', '25000944'),
(3319, 'بن عزيزة', 'عبد الرحمان', NULL, NULL, '7z3ryfs7', '$2y$10$Jf.Ged.sPVUle6upgrLF4eB6Gg4Ye9UpQArQ6hML7z5yrS56ZZt8u', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:43', '20 DT سداسي أول', '8291559188', 'نزيه بن عزيزة', '6 - 8', '25000944'),
(3320, 'بن عزيزة', 'تقوى', NULL, NULL, 'nvdnbyoy', '$2y$10$Wgslesgi/mL6H8vXIFaw3.oceJ9qOjlCr.JFsKrngl0qsaJoRVcPK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:42', '10 DT', '2641374159', 'نزيه بن عزيزة', '9 - 12/ 13-17 (للحالات الخاصة)', '25000944'),
(3321, 'الشاهد', 'ابراهيم', NULL, NULL, 'm6fva2ae', '$2y$10$UZrVr4edvQG75YtE93MTweiZ0n5eGfjjO2DvfJynBry.25c9JcOVG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:23', 'معفى', NULL, NULL, '13- 25', '56562930'),
(3322, 'الصغير', 'فاتن', NULL, NULL, '99401ee9', '$2y$10$c5hUFTD.0FoPjIUNqj8vEOXksThAvkFYcyIF9vOYqYNIXE.AD20fK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:25', '40 DT', NULL, NULL, 'فوق 26', '98685566'),
(3323, 'الزرلي', 'عمر', NULL, NULL, '88jvooca', '$2y$10$2Q2bh1w0nCO6k78qHPHsRe17SEQDOj7x7olggQHGNyIvKnfWyqqPy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:23', '40 DT', NULL, NULL, '13- 25', '50531160'),
(3324, 'قرشان', 'بوراوي', NULL, NULL, 'o37scedu', '$2y$10$BdjP3WpbXBXR2c4eVTE0MOgkjZDrUSNJPCd1GVbseJ1lhOGZvJliO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:59', '40 DT', NULL, NULL, 'فوق 26', '98576360'),
(3325, 'الجلاصي', 'أحمد', NULL, NULL, 'yhylvr37', '$2y$10$txZK8N0DEeJi9KOQDpSLnekZZFtoNZrX8yoKChooZ2yOlujQrfllG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:19', '40 DT', NULL, NULL, 'فوق 26', '98180540'),
(3326, 'موسى', 'هالة', NULL, NULL, '1a4nukgf', '$2y$10$j9Z6ItQXRelOU2zJ7LbdVu.pRJckYHAksr60cg8snVZUROzxjJAf6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:05', '40 DT', NULL, NULL, 'فوق 26', '99037910'),
(3327, 'القاضي', 'ابراهيم خليل', NULL, NULL, '6748z6pv', '$2y$10$WpswbfjeZAKzRLbaNhBci.Up8eUahDtEbwWQg1buNopEwGKOr6sru', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:30', '20 DT للعام الكامل', NULL, NULL, '13- 25', '94858833'),
(3328, 'القاضي', 'عمر الفاروق', NULL, NULL, '0mv79vor', '$2y$10$rjqW1IlrJ2Ox3y1OEmEEFudjksuojP2Jhd/k5GNhQbOrsW33DFBCm', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:30', '20 DT للعام الكامل', '7875934194', 'أمين القاضي', '9 - 12/ 13-17 (للحالات الخاصة)', '94858833'),
(3329, 'حسن', 'هارون', NULL, NULL, 'c0fjrzwt', '$2y$10$F2gxEDQ0Lhr.Oos.59C1H.b2873ZCpDLiwdzCLgiA/wpDx.7KaYRG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:51', '40 DT', '8334752581', 'عبد الستار حسن', '9 - 12/ 13-17 (للحالات الخاصة)', '94090901'),
(3330, 'حسن', 'موسى', NULL, NULL, 'xozu7g0l', '$2y$10$UzmWuk7mxDoH0WKRmLhhRe2zPRNKLwjt6weumTB7xAcfaWmLsn9JG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:51', '40 DT', '5940455105', 'عبد الستار حسن', '9 - 12/ 13-17 (للحالات الخاصة)', '98240582'),
(3331, 'البعيلي', 'أمل', NULL, NULL, '30egs1ql', '$2y$10$GXOBM6zdqWQKu5WRajJc8.Ln8mdt/akovSrqF.Gv7AvlxzgmDJ2XG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:18', '40 DT', NULL, NULL, 'فوق 26', '95489233'),
(3332, 'محجوب', 'رنيم', NULL, NULL, 'lr5827ko', '$2y$10$apSrmbF3E7Pj6tQBWhY7deLrERG1FlUEJ5OWth5DmMeyW8O3bCepG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:04', '40 DT', NULL, NULL, '13- 25', '95489233'),
(3333, 'جماقر', 'ياسمين', NULL, NULL, 'pjawphut', '$2y$10$w/TtUjGHin/434AVVdxDSOwKchJinGMOg8s2o6o88BhUP4UtxAece', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:50', '40 DT', NULL, NULL, '13- 25', '24872937'),
(3334, 'ميمونة', 'ابراهيم', NULL, NULL, 'zkd2js03', '$2y$10$HSVJTjhsc.HmqjDsajmL2uiKhXH37gwcuCKnrDr.Y4aw1WmQIOR7i', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:05', '40 DT', '8643498531', 'هشام ميمونة', '9 - 12/ 13-17 (للحالات الخاصة)', '98240857'),
(3335, 'ميمونة', 'زينب', NULL, NULL, 'gw3w6jm7', '$2y$10$zovBPPqFdKGQxbzzPNR5s.gedUcpaiPvL.qrEcmpxMYcL.plwoYri', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:06', '40 DT', NULL, NULL, '13- 25', '98240857'),
(3336, 'بن مريم', 'آزر', NULL, NULL, 'rs8fifzd', '$2y$10$5aaGqTyId2vbewncVjgHtuI8WwDonnZEIat022c5/IFnizrVyhOn2', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:43', '40 DT', '9542902133', 'انصاف زميط', '9 - 12/ 13-17 (للحالات الخاصة)', '24443666'),
(3337, 'بوهلال', 'محمد أمين', NULL, NULL, 'q85ybvc1', '$2y$10$oQcFdOza5xr6NgrPmhUEYurcvkEG0dGal/E841LIg0aF7TtPfIHi.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:47', '20 DT للعام الكامل', NULL, NULL, '13- 25', '55043104'),
(3338, 'بوهلال', 'يوسف', NULL, NULL, '445ord7p', '$2y$10$jI8GsyW8A.6mBqjk8TVMMOxbvABBo7aHzv5LjOBQDVkbjPEJ6eMNG', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:48', '20 DT للعام الكامل', '4971989826', 'حبيبة البكوش', '9 - 12/ 13-17 (للحالات الخاصة)', '55043104'),
(3339, 'هميلة', 'سوسن', NULL, NULL, 'hvr9tjem', '$2y$10$ZLkFhlZlZ61Ks0uxahxHqO5aYptX6x86eFfjPcV87iGRYwPgCiT.a', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:07', '20 DT للعام الكامل', NULL, NULL, 'فوق 26', '96345445'),
(3340, 'بوهلال', 'أحمد', NULL, NULL, '4xd5etju', '$2y$10$xOQNOBghENizeWXhExd0WeuyqOPFNsXSRQ5Rqbntan6YVyK7GtJ6m', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:45', '20 DT للعام الكامل', '5151610281', 'محمد بوهلال', '6 - 8', '99420384'),
(3341, 'السوسي', 'محمد جود', NULL, NULL, 'jykki2a8', '$2y$10$YaQCTCL2VqB5VRf.rm1Ai.OFHd/oPWGSrjlfYKfbJNW9d9Ddy/axC', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:23', '40 DT', '8429782673', 'عبد المؤمن السوسي', '6 - 8', '52041390'),
(3342, 'العابد', 'آمنة', NULL, NULL, '3hy4a4nx', '$2y$10$oKmrPgZVyfzt6SV3xROGzODsk0HPUC3dMq8KlP0aHLeT5/aVweRUe', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:26', '20 DT للعام الكامل', '5110189059', 'بسام العابد', '6 - 8', '52745103'),
(3343, 'غزال', 'ابراهيم', NULL, NULL, '9ezxybeo', '$2y$10$a95TgLnd9blRfRSOc7Y6pOptgVKQBgydV43m/SSYAVv9/cYEApkiy', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:58', '40 DT', '.', 'عمر غزال', '6 - 8', '21749035'),
(3344, 'بوقدوحة', 'ياسين', NULL, NULL, '041awsw5', '$2y$10$fkttOHWCxaPLZA2coDQ0cuAUfeSA5ttiy779mtxyikizzhX..v5SW', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:45', '40 DT', NULL, NULL, 'فوق 26', '58712610'),
(3345, 'الزرلي', 'آسيا', NULL, NULL, 'krqxspjg', '$2y$10$cFSktEOeTFVHEBo94htFVu1LnOa9uANYFZoyI.9C.S2MYiX1O3MOG', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:23', '40 DT', '.', 'أمينة جبر', '9 - 12/ 13-17 (للحالات الخاصة)', '24309033'),
(3346, 'مريزق', 'أمل', NULL, NULL, '41jcizlu', '$2y$10$e51mDGK0ACUDEiEw6oWet.g2ekfXr/sjJnZHUVMP2oYF.v0WZjoUy', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:15:04', '20 DT للعام الكامل', NULL, NULL, '13- 25', '58759009'),
(3347, 'بوقديدة', 'آمنة', NULL, NULL, 'qkfthp4j', '$2y$10$5OEb2rDa28my7AS/NrEOe.RR6814seUntQM78vUdFE2Z27JwNclIu', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:45', '40 DT', NULL, NULL, '13- 25', '29852585'),
(3348, 'بن سيك علي', 'ريان', NULL, NULL, '2edg033h', '$2y$10$a3WOm6xThZQpiu.MiZw4queNtN53Oy/JU1fKTDLfT/E6KJWi05PrO', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:40', '10 DT', '3273904186', 'طاهر بن سيك علي', '9 - 12/ 13-17 (للحالات الخاصة)', '97754600'),
(3349, 'المخينيني', 'إسراء', NULL, NULL, 'was56uvz', '$2y$10$hecwA5WN/SO46896V.QXBuAlrknLL6H2fqeKhTB4.T77vtftWC3LK', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:17', '2026-02-28 21:14:33', '20 د السداسي الثاني', '3381926117', 'كريم المخينيني', '6 - 8', '98287546'),
(3350, 'المخينيني', 'اسلام', NULL, NULL, 'jgocjwu1', '$2y$10$m2Qb8XI0YTmjSnH9NY/NSOLPdR79V.p2gbEmaG7Uw4HDHLB3YGXaq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:33', '20 د السداسي الثاني', '8519265678', 'كريم المخينيني', '9 - 12/ 13-17 (للحالات الخاصة)', '98287546'),
(3351, 'قليم', 'زينب', NULL, NULL, 'bd3tv1m4', '$2y$10$VExcXsitJDiZBg9r3aXJUegYBpaEeTCKfQZZiBLgiyLPtGGPFypLq', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:15:02', '20 د السداسي الثاني', '6110943921', 'أحمد قليم', '6 - 8', '98191332'),
(3352, 'قليم', 'إبراهيم', NULL, NULL, 'xfs9xh66', '$2y$10$d9fwRm98jn4guPwJJkJk7OMeAI1BUt3PNoES485.dD9JRVtNhRC..', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:15:02', '20 د السداسي الثاني', '1744167508', 'أحمد قليم', '9 - 12/ 13-17 (للحالات الخاصة)', '98191332'),
(3353, 'مليس', 'مجدي', NULL, NULL, 'n2qs4igh', '$2y$10$2QQQtc7Vt51kO7C7LN/Nh.1QfVGTmqRJ8.eTFPn6XgZWFOzqk9Shq', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:15:05', '20 د السداسي الثاني', NULL, NULL, 'فوق 26', '50835624'),
(3354, 'الميساوي', 'همسة', NULL, NULL, '3qy7svig', '$2y$10$xvBjiiji01MMOslRlP3Tpendtm/A.5sp/jsRVN.6CxKpa4qatVGVW', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:34', '20 د السداسي الثاني', '2135218459', 'وسام الميساوي', '9 - 12/ 13-17 (للحالات الخاصة)', '98554920'),
(3355, 'بوفارس', 'فاطمة الزهراء', NULL, NULL, 'xrm45kjc', '$2y$10$xJOrhdKzjfeAnJ4QE0EPou/.3SE1e6lTKoPhuIEd3ZnXecHbFGG0e', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:45', '40 DT', NULL, NULL, '13- 25', '28805907'),
(3356, 'بوفارس', 'زينب', NULL, NULL, 'l7sw6omm', '$2y$10$L6yzXk3jSnBIU8kq434a5.eBYSE.thzr.U7w8n6Qk32mNSEMoRrei', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:45', '20 د السداسي الثاني', NULL, NULL, '13- 25', '28805907'),
(3357, 'بية الشطي', 'آمال', NULL, NULL, 'wk9t6i8h', '$2y$10$VFNTHIDRwJg03w6nhGH1ie67ji/IaLwzMUiiWlBZJ/IneCh6OPHJ6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:48', '20 د السداسي الثاني', NULL, NULL, 'فوق 26', '52075817'),
(3358, 'بن حسين', 'أمينة', NULL, NULL, 'xxlo1n1k', '$2y$10$SpIA/reZDrbibL5sdSQmVe/zTW4ZEspPTw.3ihKKT62dBmh413v7S', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:38', '20 د السداسي الثاني', NULL, NULL, 'فوق 26', '52981510'),
(3359, 'بن الحاج خليفة', 'سنية', NULL, NULL, 'cm5rlm79', '$2y$10$xV6OD5W/zJMvoZJCygAJ/OFfbKIfUBs.2PHcWXJCw8Fr6ihrJd3je', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:37', '20 د السداسي الثاني', NULL, NULL, 'فوق 26', '93165650'),
(3360, 'كشيش', 'أيوب', NULL, NULL, 'mt42w033', '$2y$10$Zx.W9YtPznL6Dogcx5CMAuB4Evxx8lPWpHYuCW1tmmA7nh.r0yKq.', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:15:03', '20 د السداسي الثاني', '4171918668', 'سنية بن الحاج خليفة', '9 - 12/ 13-17 (للحالات الخاصة)', '93165650'),
(3361, 'كشيش', 'مريم', NULL, NULL, '3a58hy5l', '$2y$10$3M9bQcwN2pO.Nt6U06VnzuY36SokY/sGx.vP.WKM9NVcD2aYfUiAa', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:15:03', '20 د السداسي الثاني', '4665457502', 'سنية', '6 - 8', '93165650'),
(3362, 'يعقوبي', 'إبراهيم', NULL, NULL, 'lj8c97qk', '$2y$10$HGn7GwcDpI1pYExYBUHnNOz7vwOd/i/d5DGnhbV.Xe9iEOCQDbj.e', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:15:08', '20 د السداسي الثاني', '8844124439', 'نجوى قعيدة محجوب', '9 - 12/ 13-17 (للحالات الخاصة)', '24337739'),
(3363, 'يعقوبي', 'فاطمة', NULL, NULL, '5erqk19j', '$2y$10$KdPp921FafnlngCunwS/2eOT8.fs2OuEpOihmC7cvw0OIbx/oo6lm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:15:08', '20 د السداسي الثاني', '4122557085', 'نجوى قعيدة محجوب', '9 - 12/ 13-17 (للحالات الخاصة)', '24337739'),
(3364, 'غزال', 'ياسين', NULL, NULL, 'muivf10p', '$2y$10$MIeo9kN6TSXnODZGBbQ7euXDeEYZk8DKwkPHZs4doR6YEZI1/K57O', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:59', '20 د السداسي الثاني', '2344084317', 'عمر غزال', '9 - 12/ 13-17 (للحالات الخاصة)', '21749035'),
(3365, 'شكري', 'أحمد براء', NULL, NULL, 'a9y4ho6n', '$2y$10$WpXLdMP8rVrHTecyV2fUnuQ7vl1AGQi7AIu7lpdKcIC0VJ2Fvmg0y', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:55', '20 د السداسي الثاني', '2309197659', 'رمزي شكري', '9 - 12/ 13-17 (للحالات الخاصة)', '97393183'),
(3366, 'شكري', 'عبد الرحمن', NULL, NULL, 'pxlkns2b', '$2y$10$0qSvoA3uvXHxAQ1x8cHBWupyCaYaHBDdD7xyBaiQ1AXMyOa7BNCwu', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:55', '20 د السداسي الثاني', '9616604450', 'رمزي شكري', '9 - 12/ 13-17 (للحالات الخاصة)', '97393183'),
(3367, 'علبوشي', 'ميارى', NULL, NULL, '1kedcj82', '$2y$10$SfbdJAEdXxfd8SclNHfiZuiDgMzEMBffV.hqxSCx1r6EU/RRr7ui6', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:57', '20 د السداسي الثاني', NULL, NULL, '13- 25', '95681749'),
(3368, 'الصريدي', 'حمزة', NULL, NULL, 'vutxicxa', '$2y$10$nIrWPodfaQt3aqbuGRrqYOGDU9wSM8gWgN8JjSa80/AKM.3fq.nXa', NULL, NULL, 'ذكر', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:25', '20 د السداسي الثاني', NULL, NULL, 'فوق 26', '56198183'),
(3369, 'بن حمودة', 'عبير', NULL, NULL, 's430rl7k', '$2y$10$Fpwy2sa6/Zy/z1N2dei4mexjWgg6lJKIcLKEgN4wiJLHqSSiv0kXm', NULL, NULL, 'أنثى', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-28 21:12:18', '2026-02-28 21:14:39', '20 د السداسي الثاني', NULL, NULL, 'فوق 26', '99620033/97597191');

-- --------------------------------------------------------

--
-- Table structure for table `students_join_address`
--

CREATE TABLE `students_join_address` (
  `id` int NOT NULL,
  `student_id` int NOT NULL,
  `address_id` int NOT NULL,
  `contact_seq` decimal(10,0) DEFAULT NULL,
  `gets_mail` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `primary_residence` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `legal_residence` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `am_bus` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `pm_bus` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mailing` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `residence` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus_pickup` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus_dropoff` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_join_people`
--

CREATE TABLE `students_join_people` (
  `id` int NOT NULL,
  `student_id` int NOT NULL,
  `person_id` int NOT NULL,
  `address_id` int DEFAULT NULL,
  `custody` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `emergency` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `student_relation` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_join_users`
--

CREATE TABLE `students_join_users` (
  `student_id` int NOT NULL,
  `staff_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_assignments`
--

CREATE TABLE `student_assignments` (
  `assignment_id` int NOT NULL,
  `student_id` int NOT NULL,
  `data` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_eligibility_activities`
--

CREATE TABLE `student_eligibility_activities` (
  `syear` decimal(4,0) DEFAULT NULL,
  `student_id` int NOT NULL,
  `activity_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_enrollment`
--

CREATE TABLE `student_enrollment` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `student_id` int NOT NULL,
  `grade_id` int DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `enrollment_code` int DEFAULT NULL,
  `drop_code` int DEFAULT NULL,
  `next_school` int DEFAULT NULL,
  `calendar_id` int DEFAULT NULL,
  `last_school` int DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_enrollment`
--

INSERT INTO `student_enrollment` (`id`, `syear`, `school_id`, `student_id`, `grade_id`, `start_date`, `end_date`, `enrollment_code`, `drop_code`, `next_school`, `calendar_id`, `last_school`, `created_at`, `updated_at`) VALUES
(843, '2025', 1, 2528, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(844, '2025', 1, 2529, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(845, '2025', 1, 2530, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(846, '2025', 1, 2531, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(847, '2025', 1, 2532, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(848, '2025', 1, 2533, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(849, '2025', 1, 2534, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(850, '2025', 1, 2535, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(851, '2025', 1, 2536, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(852, '2025', 1, 2537, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(853, '2025', 1, 2538, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(854, '2025', 1, 2539, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(855, '2025', 1, 2540, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(856, '2025', 1, 2541, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(857, '2025', 1, 2542, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(858, '2025', 1, 2543, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(859, '2025', 1, 2544, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(860, '2025', 1, 2545, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(861, '2025', 1, 2546, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(862, '2025', 1, 2547, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(863, '2025', 1, 2548, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(864, '2025', 1, 2549, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(865, '2025', 1, 2550, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(866, '2025', 1, 2551, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(867, '2025', 1, 2552, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(868, '2025', 1, 2553, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(869, '2025', 1, 2554, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(870, '2025', 1, 2555, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(871, '2025', 1, 2556, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(872, '2025', 1, 2557, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(873, '2025', 1, 2558, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(874, '2025', 1, 2559, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(875, '2025', 1, 2560, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(876, '2025', 1, 2561, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(877, '2025', 1, 2562, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(878, '2025', 1, 2563, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(879, '2025', 1, 2564, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(880, '2025', 1, 2565, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(881, '2025', 1, 2566, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(882, '2025', 1, 2567, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(883, '2025', 1, 2568, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(884, '2025', 1, 2569, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(885, '2025', 1, 2570, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(886, '2025', 1, 2571, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(887, '2025', 1, 2572, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(888, '2025', 1, 2573, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(889, '2025', 1, 2574, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:11:59', NULL),
(890, '2025', 1, 2575, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(891, '2025', 1, 2576, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(892, '2025', 1, 2577, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(893, '2025', 1, 2578, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(894, '2025', 1, 2579, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(895, '2025', 1, 2580, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(896, '2025', 1, 2581, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(897, '2025', 1, 2582, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(898, '2025', 1, 2583, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(899, '2025', 1, 2584, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(900, '2025', 1, 2585, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(901, '2025', 1, 2586, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(902, '2025', 1, 2587, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(903, '2025', 1, 2588, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(904, '2025', 1, 2589, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(905, '2025', 1, 2590, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(906, '2025', 1, 2591, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(907, '2025', 1, 2592, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(908, '2025', 1, 2593, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(909, '2025', 1, 2594, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(910, '2025', 1, 2595, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(911, '2025', 1, 2596, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(912, '2025', 1, 2597, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(913, '2025', 1, 2598, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(914, '2025', 1, 2599, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(915, '2025', 1, 2600, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(916, '2025', 1, 2601, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(917, '2025', 1, 2602, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(918, '2025', 1, 2603, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(919, '2025', 1, 2604, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(920, '2025', 1, 2605, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(921, '2025', 1, 2606, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(922, '2025', 1, 2607, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(923, '2025', 1, 2608, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(924, '2025', 1, 2609, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(925, '2025', 1, 2610, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(926, '2025', 1, 2611, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(927, '2025', 1, 2612, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(928, '2025', 1, 2613, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(929, '2025', 1, 2614, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(930, '2025', 1, 2615, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(931, '2025', 1, 2616, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(932, '2025', 1, 2617, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(933, '2025', 1, 2618, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(934, '2025', 1, 2619, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:00', NULL),
(935, '2025', 1, 2620, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(936, '2025', 1, 2621, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(937, '2025', 1, 2622, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(938, '2025', 1, 2623, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(939, '2025', 1, 2624, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(940, '2025', 1, 2625, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(941, '2025', 1, 2626, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(942, '2025', 1, 2627, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(943, '2025', 1, 2628, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(944, '2025', 1, 2629, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(945, '2025', 1, 2630, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(946, '2025', 1, 2631, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(947, '2025', 1, 2632, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(948, '2025', 1, 2633, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(949, '2025', 1, 2634, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(950, '2025', 1, 2635, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(951, '2025', 1, 2636, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(952, '2025', 1, 2637, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(953, '2025', 1, 2638, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(954, '2025', 1, 2639, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(955, '2025', 1, 2640, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(956, '2025', 1, 2641, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(957, '2025', 1, 2642, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(958, '2025', 1, 2643, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(959, '2025', 1, 2644, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(960, '2025', 1, 2645, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(961, '2025', 1, 2646, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(962, '2025', 1, 2647, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(963, '2025', 1, 2648, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(964, '2025', 1, 2649, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(965, '2025', 1, 2650, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(966, '2025', 1, 2651, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(967, '2025', 1, 2652, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(968, '2025', 1, 2653, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(969, '2025', 1, 2654, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(970, '2025', 1, 2655, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(971, '2025', 1, 2656, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(972, '2025', 1, 2657, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(973, '2025', 1, 2658, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(974, '2025', 1, 2659, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(975, '2025', 1, 2660, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(976, '2025', 1, 2661, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(977, '2025', 1, 2662, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(978, '2025', 1, 2663, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(979, '2025', 1, 2664, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(980, '2025', 1, 2665, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(981, '2025', 1, 2666, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:01', NULL),
(982, '2025', 1, 2667, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(983, '2025', 1, 2668, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(984, '2025', 1, 2669, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(985, '2025', 1, 2670, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(986, '2025', 1, 2671, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(987, '2025', 1, 2672, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(988, '2025', 1, 2673, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(989, '2025', 1, 2674, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(990, '2025', 1, 2675, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(991, '2025', 1, 2676, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(992, '2025', 1, 2677, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(993, '2025', 1, 2678, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(994, '2025', 1, 2679, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(995, '2025', 1, 2680, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(996, '2025', 1, 2681, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(997, '2025', 1, 2682, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(998, '2025', 1, 2683, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(999, '2025', 1, 2684, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1000, '2025', 1, 2685, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1001, '2025', 1, 2686, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1002, '2025', 1, 2687, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1003, '2025', 1, 2688, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1004, '2025', 1, 2689, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1005, '2025', 1, 2690, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1006, '2025', 1, 2691, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1007, '2025', 1, 2692, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1008, '2025', 1, 2693, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1009, '2025', 1, 2694, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1010, '2025', 1, 2695, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1011, '2025', 1, 2696, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1012, '2025', 1, 2697, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1013, '2025', 1, 2698, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1014, '2025', 1, 2699, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1015, '2025', 1, 2700, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1016, '2025', 1, 2701, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1017, '2025', 1, 2702, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1018, '2025', 1, 2703, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1019, '2025', 1, 2704, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1020, '2025', 1, 2705, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1021, '2025', 1, 2706, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1022, '2025', 1, 2707, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1023, '2025', 1, 2708, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1024, '2025', 1, 2709, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1025, '2025', 1, 2710, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1026, '2025', 1, 2711, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1027, '2025', 1, 2712, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:02', NULL),
(1028, '2025', 1, 2713, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1029, '2025', 1, 2714, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1030, '2025', 1, 2715, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1031, '2025', 1, 2716, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1032, '2025', 1, 2717, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1033, '2025', 1, 2718, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1034, '2025', 1, 2719, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1035, '2025', 1, 2720, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1036, '2025', 1, 2721, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1037, '2025', 1, 2722, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1038, '2025', 1, 2723, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1039, '2025', 1, 2724, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1040, '2025', 1, 2725, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1041, '2025', 1, 2726, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1042, '2025', 1, 2727, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1043, '2025', 1, 2728, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1044, '2025', 1, 2729, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1045, '2025', 1, 2730, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1046, '2025', 1, 2731, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1047, '2025', 1, 2732, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1048, '2025', 1, 2733, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1049, '2025', 1, 2734, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1050, '2025', 1, 2735, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1051, '2025', 1, 2736, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1052, '2025', 1, 2737, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1053, '2025', 1, 2738, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1054, '2025', 1, 2739, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1055, '2025', 1, 2740, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1056, '2025', 1, 2741, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1057, '2025', 1, 2742, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1058, '2025', 1, 2743, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1059, '2025', 1, 2744, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1060, '2025', 1, 2745, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1061, '2025', 1, 2746, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1062, '2025', 1, 2747, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1063, '2025', 1, 2748, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1064, '2025', 1, 2749, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1065, '2025', 1, 2750, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1066, '2025', 1, 2751, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1067, '2025', 1, 2752, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1068, '2025', 1, 2753, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1069, '2025', 1, 2754, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1070, '2025', 1, 2755, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1071, '2025', 1, 2756, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1072, '2025', 1, 2757, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1073, '2025', 1, 2758, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1074, '2025', 1, 2759, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1075, '2025', 1, 2760, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1076, '2025', 1, 2761, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:03', NULL),
(1077, '2025', 1, 2762, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1078, '2025', 1, 2763, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1079, '2025', 1, 2764, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1080, '2025', 1, 2765, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1081, '2025', 1, 2766, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1082, '2025', 1, 2767, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1083, '2025', 1, 2768, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1084, '2025', 1, 2769, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1085, '2025', 1, 2770, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1086, '2025', 1, 2771, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1087, '2025', 1, 2772, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1088, '2025', 1, 2773, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1089, '2025', 1, 2774, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1090, '2025', 1, 2775, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1091, '2025', 1, 2776, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1092, '2025', 1, 2777, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1093, '2025', 1, 2778, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1094, '2025', 1, 2779, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1095, '2025', 1, 2780, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1096, '2025', 1, 2781, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1097, '2025', 1, 2782, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1098, '2025', 1, 2783, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1099, '2025', 1, 2784, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1100, '2025', 1, 2785, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1101, '2025', 1, 2786, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1102, '2025', 1, 2787, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1103, '2025', 1, 2788, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1104, '2025', 1, 2789, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1105, '2025', 1, 2790, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1106, '2025', 1, 2791, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1107, '2025', 1, 2792, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1108, '2025', 1, 2793, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1109, '2025', 1, 2794, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1110, '2025', 1, 2795, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1111, '2025', 1, 2796, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1112, '2025', 1, 2797, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1113, '2025', 1, 2798, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1114, '2025', 1, 2799, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1115, '2025', 1, 2800, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1116, '2025', 1, 2801, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1117, '2025', 1, 2802, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1118, '2025', 1, 2803, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1119, '2025', 1, 2804, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1120, '2025', 1, 2805, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1121, '2025', 1, 2806, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1122, '2025', 1, 2807, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1123, '2025', 1, 2808, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1124, '2025', 1, 2809, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1125, '2025', 1, 2810, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1126, '2025', 1, 2811, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1127, '2025', 1, 2812, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1128, '2025', 1, 2813, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:04', NULL),
(1129, '2025', 1, 2814, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1130, '2025', 1, 2815, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1131, '2025', 1, 2816, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1132, '2025', 1, 2817, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1133, '2025', 1, 2818, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1134, '2025', 1, 2819, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1135, '2025', 1, 2820, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1136, '2025', 1, 2821, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1137, '2025', 1, 2822, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1138, '2025', 1, 2823, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1139, '2025', 1, 2824, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1140, '2025', 1, 2825, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1141, '2025', 1, 2826, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1142, '2025', 1, 2827, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1143, '2025', 1, 2828, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1144, '2025', 1, 2829, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1145, '2025', 1, 2830, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1146, '2025', 1, 2831, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1147, '2025', 1, 2832, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1148, '2025', 1, 2833, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1149, '2025', 1, 2834, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1150, '2025', 1, 2835, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1151, '2025', 1, 2836, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1152, '2025', 1, 2837, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1153, '2025', 1, 2838, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1154, '2025', 1, 2839, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1155, '2025', 1, 2840, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1156, '2025', 1, 2841, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1157, '2025', 1, 2842, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1158, '2025', 1, 2843, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1159, '2025', 1, 2844, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1160, '2025', 1, 2845, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1161, '2025', 1, 2846, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1162, '2025', 1, 2847, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1163, '2025', 1, 2848, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1164, '2025', 1, 2849, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1165, '2025', 1, 2850, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1166, '2025', 1, 2851, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1167, '2025', 1, 2852, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1168, '2025', 1, 2853, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1169, '2025', 1, 2854, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1170, '2025', 1, 2855, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1171, '2025', 1, 2856, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1172, '2025', 1, 2857, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1173, '2025', 1, 2858, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1174, '2025', 1, 2859, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1175, '2025', 1, 2860, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:05', NULL),
(1176, '2025', 1, 2861, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1177, '2025', 1, 2862, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1178, '2025', 1, 2863, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1179, '2025', 1, 2864, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1180, '2025', 1, 2865, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1181, '2025', 1, 2866, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1182, '2025', 1, 2867, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1183, '2025', 1, 2868, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1184, '2025', 1, 2869, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1185, '2025', 1, 2870, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1186, '2025', 1, 2871, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1187, '2025', 1, 2872, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1188, '2025', 1, 2873, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1189, '2025', 1, 2874, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1190, '2025', 1, 2875, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1191, '2025', 1, 2876, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1192, '2025', 1, 2877, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1193, '2025', 1, 2878, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1194, '2025', 1, 2879, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1195, '2025', 1, 2880, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1196, '2025', 1, 2881, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1197, '2025', 1, 2882, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1198, '2025', 1, 2883, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1199, '2025', 1, 2884, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1200, '2025', 1, 2885, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1201, '2025', 1, 2886, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1202, '2025', 1, 2887, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1203, '2025', 1, 2888, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1204, '2025', 1, 2889, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1205, '2025', 1, 2890, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1206, '2025', 1, 2891, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1207, '2025', 1, 2892, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1208, '2025', 1, 2893, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1209, '2025', 1, 2894, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1210, '2025', 1, 2895, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1211, '2025', 1, 2896, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1212, '2025', 1, 2897, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1213, '2025', 1, 2898, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1214, '2025', 1, 2899, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1215, '2025', 1, 2900, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1216, '2025', 1, 2901, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1217, '2025', 1, 2902, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1218, '2025', 1, 2903, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1219, '2025', 1, 2904, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1220, '2025', 1, 2905, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:06', NULL),
(1221, '2025', 1, 2906, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1222, '2025', 1, 2907, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1223, '2025', 1, 2908, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1224, '2025', 1, 2909, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1225, '2025', 1, 2910, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1226, '2025', 1, 2911, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1227, '2025', 1, 2912, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1228, '2025', 1, 2913, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1229, '2025', 1, 2914, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1230, '2025', 1, 2915, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1231, '2025', 1, 2916, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1232, '2025', 1, 2917, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1233, '2025', 1, 2918, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1234, '2025', 1, 2919, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1235, '2025', 1, 2920, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1236, '2025', 1, 2921, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1237, '2025', 1, 2922, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1238, '2025', 1, 2923, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1239, '2025', 1, 2924, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1240, '2025', 1, 2925, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1241, '2025', 1, 2926, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1242, '2025', 1, 2927, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1243, '2025', 1, 2928, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1244, '2025', 1, 2929, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1245, '2025', 1, 2930, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1246, '2025', 1, 2931, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1247, '2025', 1, 2932, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1248, '2025', 1, 2933, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1249, '2025', 1, 2934, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1250, '2025', 1, 2935, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1251, '2025', 1, 2936, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1252, '2025', 1, 2937, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1253, '2025', 1, 2938, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1254, '2025', 1, 2939, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1255, '2025', 1, 2940, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1256, '2025', 1, 2941, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1257, '2025', 1, 2942, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1258, '2025', 1, 2943, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1259, '2025', 1, 2944, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1260, '2025', 1, 2945, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1261, '2025', 1, 2946, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1262, '2025', 1, 2947, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1263, '2025', 1, 2948, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1264, '2025', 1, 2949, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:07', NULL),
(1265, '2025', 1, 2950, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1266, '2025', 1, 2951, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1267, '2025', 1, 2952, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1268, '2025', 1, 2953, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1269, '2025', 1, 2954, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1270, '2025', 1, 2955, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1271, '2025', 1, 2956, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1272, '2025', 1, 2957, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1273, '2025', 1, 2958, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1274, '2025', 1, 2959, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1275, '2025', 1, 2960, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1276, '2025', 1, 2961, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1277, '2025', 1, 2962, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1278, '2025', 1, 2963, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1279, '2025', 1, 2964, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1280, '2025', 1, 2965, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1281, '2025', 1, 2966, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1282, '2025', 1, 2967, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1283, '2025', 1, 2968, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1284, '2025', 1, 2969, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1285, '2025', 1, 2970, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1286, '2025', 1, 2971, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1287, '2025', 1, 2972, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1288, '2025', 1, 2973, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1289, '2025', 1, 2974, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1290, '2025', 1, 2975, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1291, '2025', 1, 2976, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1292, '2025', 1, 2977, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1293, '2025', 1, 2978, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1294, '2025', 1, 2979, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1295, '2025', 1, 2980, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1296, '2025', 1, 2981, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1297, '2025', 1, 2982, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1298, '2025', 1, 2983, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1299, '2025', 1, 2984, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1300, '2025', 1, 2985, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1301, '2025', 1, 2986, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1302, '2025', 1, 2987, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1303, '2025', 1, 2988, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:08', NULL),
(1304, '2025', 1, 2989, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1305, '2025', 1, 2990, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1306, '2025', 1, 2991, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1307, '2025', 1, 2992, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1308, '2025', 1, 2993, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1309, '2025', 1, 2994, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1310, '2025', 1, 2995, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1311, '2025', 1, 2996, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1312, '2025', 1, 2997, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1313, '2025', 1, 2998, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1314, '2025', 1, 2999, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1315, '2025', 1, 3000, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1316, '2025', 1, 3001, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1317, '2025', 1, 3002, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1318, '2025', 1, 3003, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1319, '2025', 1, 3004, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1320, '2025', 1, 3005, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1321, '2025', 1, 3006, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1322, '2025', 1, 3007, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1323, '2025', 1, 3008, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1324, '2025', 1, 3009, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1325, '2025', 1, 3010, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1326, '2025', 1, 3011, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1327, '2025', 1, 3012, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1328, '2025', 1, 3013, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1329, '2025', 1, 3014, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1330, '2025', 1, 3015, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1331, '2025', 1, 3016, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1332, '2025', 1, 3017, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1333, '2025', 1, 3018, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1334, '2025', 1, 3019, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1335, '2025', 1, 3020, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1336, '2025', 1, 3021, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1337, '2025', 1, 3022, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1338, '2025', 1, 3023, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1339, '2025', 1, 3024, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:09', NULL),
(1340, '2025', 1, 3025, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1341, '2025', 1, 3026, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1342, '2025', 1, 3027, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1343, '2025', 1, 3028, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1344, '2025', 1, 3029, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1345, '2025', 1, 3030, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1346, '2025', 1, 3031, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1347, '2025', 1, 3032, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1348, '2025', 1, 3033, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1349, '2025', 1, 3034, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1350, '2025', 1, 3035, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1351, '2025', 1, 3036, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1352, '2025', 1, 3037, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1353, '2025', 1, 3038, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1354, '2025', 1, 3039, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1355, '2025', 1, 3040, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1356, '2025', 1, 3041, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1357, '2025', 1, 3042, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1358, '2025', 1, 3043, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1359, '2025', 1, 3044, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL);
INSERT INTO `student_enrollment` (`id`, `syear`, `school_id`, `student_id`, `grade_id`, `start_date`, `end_date`, `enrollment_code`, `drop_code`, `next_school`, `calendar_id`, `last_school`, `created_at`, `updated_at`) VALUES
(1360, '2025', 1, 3045, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1361, '2025', 1, 3046, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1362, '2025', 1, 3047, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1363, '2025', 1, 3048, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1364, '2025', 1, 3049, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1365, '2025', 1, 3050, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1366, '2025', 1, 3051, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1367, '2025', 1, 3052, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1368, '2025', 1, 3053, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1369, '2025', 1, 3054, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1370, '2025', 1, 3055, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1371, '2025', 1, 3056, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1372, '2025', 1, 3057, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1373, '2025', 1, 3058, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1374, '2025', 1, 3059, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1375, '2025', 1, 3060, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1376, '2025', 1, 3061, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1377, '2025', 1, 3062, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1378, '2025', 1, 3063, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1379, '2025', 1, 3064, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1380, '2025', 1, 3065, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1381, '2025', 1, 3066, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:10', NULL),
(1382, '2025', 1, 3067, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1383, '2025', 1, 3068, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1384, '2025', 1, 3069, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1385, '2025', 1, 3070, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1386, '2025', 1, 3071, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1387, '2025', 1, 3072, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1388, '2025', 1, 3073, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1389, '2025', 1, 3074, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1390, '2025', 1, 3075, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1391, '2025', 1, 3076, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1392, '2025', 1, 3077, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1393, '2025', 1, 3078, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1394, '2025', 1, 3079, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1395, '2025', 1, 3080, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1396, '2025', 1, 3081, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1397, '2025', 1, 3082, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1398, '2025', 1, 3083, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1399, '2025', 1, 3084, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1400, '2025', 1, 3085, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1401, '2025', 1, 3086, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1402, '2025', 1, 3087, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1403, '2025', 1, 3088, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1404, '2025', 1, 3089, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1405, '2025', 1, 3090, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1406, '2025', 1, 3091, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1407, '2025', 1, 3092, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1408, '2025', 1, 3093, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1409, '2025', 1, 3094, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1410, '2025', 1, 3095, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1411, '2025', 1, 3096, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1412, '2025', 1, 3097, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1413, '2025', 1, 3098, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1414, '2025', 1, 3099, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1415, '2025', 1, 3100, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1416, '2025', 1, 3101, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1417, '2025', 1, 3102, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1418, '2025', 1, 3103, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1419, '2025', 1, 3104, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1420, '2025', 1, 3105, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1421, '2025', 1, 3106, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1422, '2025', 1, 3107, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:11', NULL),
(1423, '2025', 1, 3108, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1424, '2025', 1, 3109, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1425, '2025', 1, 3110, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1426, '2025', 1, 3111, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1427, '2025', 1, 3112, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1428, '2025', 1, 3113, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1429, '2025', 1, 3114, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1430, '2025', 1, 3115, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1431, '2025', 1, 3116, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1432, '2025', 1, 3117, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1433, '2025', 1, 3118, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1434, '2025', 1, 3119, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1435, '2025', 1, 3120, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1436, '2025', 1, 3121, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1437, '2025', 1, 3122, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1438, '2025', 1, 3123, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1439, '2025', 1, 3124, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1440, '2025', 1, 3125, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1441, '2025', 1, 3126, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1442, '2025', 1, 3127, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1443, '2025', 1, 3128, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1444, '2025', 1, 3129, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1445, '2025', 1, 3130, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1446, '2025', 1, 3131, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1447, '2025', 1, 3132, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1448, '2025', 1, 3133, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1449, '2025', 1, 3134, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1450, '2025', 1, 3135, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1451, '2025', 1, 3136, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1452, '2025', 1, 3137, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1453, '2025', 1, 3138, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1454, '2025', 1, 3139, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1455, '2025', 1, 3140, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1456, '2025', 1, 3141, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1457, '2025', 1, 3142, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1458, '2025', 1, 3143, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1459, '2025', 1, 3144, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1460, '2025', 1, 3145, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1461, '2025', 1, 3146, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1462, '2025', 1, 3147, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:12', NULL),
(1463, '2025', 1, 3148, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1464, '2025', 1, 3149, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1465, '2025', 1, 3150, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1466, '2025', 1, 3151, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1467, '2025', 1, 3152, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1468, '2025', 1, 3153, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1469, '2025', 1, 3154, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1470, '2025', 1, 3155, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1471, '2025', 1, 3156, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1472, '2025', 1, 3157, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1473, '2025', 1, 3158, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1474, '2025', 1, 3159, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1475, '2025', 1, 3160, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1476, '2025', 1, 3161, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1477, '2025', 1, 3162, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1478, '2025', 1, 3163, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1479, '2025', 1, 3164, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1480, '2025', 1, 3165, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1481, '2025', 1, 3166, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1482, '2025', 1, 3167, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1483, '2025', 1, 3168, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1484, '2025', 1, 3169, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1485, '2025', 1, 3170, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1486, '2025', 1, 3171, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1487, '2025', 1, 3172, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1488, '2025', 1, 3173, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1489, '2025', 1, 3174, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1490, '2025', 1, 3175, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1491, '2025', 1, 3176, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1492, '2025', 1, 3177, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1493, '2025', 1, 3178, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1494, '2025', 1, 3179, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1495, '2025', 1, 3180, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1496, '2025', 1, 3181, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1497, '2025', 1, 3182, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1498, '2025', 1, 3183, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1499, '2025', 1, 3184, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1500, '2025', 1, 3185, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1501, '2025', 1, 3186, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1502, '2025', 1, 3187, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1503, '2025', 1, 3188, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1504, '2025', 1, 3189, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:13', NULL),
(1505, '2025', 1, 3190, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1506, '2025', 1, 3191, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1507, '2025', 1, 3192, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1508, '2025', 1, 3193, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1509, '2025', 1, 3194, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1510, '2025', 1, 3195, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1511, '2025', 1, 3196, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1512, '2025', 1, 3197, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1513, '2025', 1, 3198, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1514, '2025', 1, 3199, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1515, '2025', 1, 3200, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1516, '2025', 1, 3201, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1517, '2025', 1, 3202, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1518, '2025', 1, 3203, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1519, '2025', 1, 3204, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1520, '2025', 1, 3205, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1521, '2025', 1, 3206, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1522, '2025', 1, 3207, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1523, '2025', 1, 3208, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1524, '2025', 1, 3209, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1525, '2025', 1, 3210, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1526, '2025', 1, 3211, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1527, '2025', 1, 3212, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1528, '2025', 1, 3213, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1529, '2025', 1, 3214, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1530, '2025', 1, 3215, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1531, '2025', 1, 3216, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1532, '2025', 1, 3217, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1533, '2025', 1, 3218, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1534, '2025', 1, 3219, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1535, '2025', 1, 3220, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1536, '2025', 1, 3221, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1537, '2025', 1, 3222, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1538, '2025', 1, 3223, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1539, '2025', 1, 3224, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1540, '2025', 1, 3225, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1541, '2025', 1, 3226, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1542, '2025', 1, 3227, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1543, '2025', 1, 3228, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1544, '2025', 1, 3229, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:14', NULL),
(1545, '2025', 1, 3230, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1546, '2025', 1, 3231, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1547, '2025', 1, 3232, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1548, '2025', 1, 3233, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1549, '2025', 1, 3234, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1550, '2025', 1, 3235, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1551, '2025', 1, 3236, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1552, '2025', 1, 3237, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1553, '2025', 1, 3238, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1554, '2025', 1, 3239, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1555, '2025', 1, 3240, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1556, '2025', 1, 3241, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1557, '2025', 1, 3242, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1558, '2025', 1, 3243, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1559, '2025', 1, 3244, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1560, '2025', 1, 3245, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1561, '2025', 1, 3246, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1562, '2025', 1, 3247, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1563, '2025', 1, 3248, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1564, '2025', 1, 3249, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1565, '2025', 1, 3250, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1566, '2025', 1, 3251, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1567, '2025', 1, 3252, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1568, '2025', 1, 3253, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1569, '2025', 1, 3254, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1570, '2025', 1, 3255, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1571, '2025', 1, 3256, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1572, '2025', 1, 3257, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1573, '2025', 1, 3258, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1574, '2025', 1, 3259, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1575, '2025', 1, 3260, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1576, '2025', 1, 3261, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1577, '2025', 1, 3262, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1578, '2025', 1, 3263, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1579, '2025', 1, 3264, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1580, '2025', 1, 3265, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1581, '2025', 1, 3266, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:15', NULL),
(1582, '2025', 1, 3267, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1583, '2025', 1, 3268, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1584, '2025', 1, 3269, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1585, '2025', 1, 3270, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1586, '2025', 1, 3271, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1587, '2025', 1, 3272, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1588, '2025', 1, 3273, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1589, '2025', 1, 3274, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1590, '2025', 1, 3275, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1591, '2025', 1, 3276, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1592, '2025', 1, 3277, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1593, '2025', 1, 3278, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1594, '2025', 1, 3279, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1595, '2025', 1, 3280, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1596, '2025', 1, 3281, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1597, '2025', 1, 3282, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1598, '2025', 1, 3283, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1599, '2025', 1, 3284, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1600, '2025', 1, 3285, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1601, '2025', 1, 3286, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1602, '2025', 1, 3287, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1603, '2025', 1, 3288, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1604, '2025', 1, 3289, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1605, '2025', 1, 3290, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1606, '2025', 1, 3291, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1607, '2025', 1, 3292, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1608, '2025', 1, 3293, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1609, '2025', 1, 3294, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1610, '2025', 1, 3295, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1611, '2025', 1, 3296, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1612, '2025', 1, 3297, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1613, '2025', 1, 3298, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1614, '2025', 1, 3299, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1615, '2025', 1, 3300, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1616, '2025', 1, 3301, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1617, '2025', 1, 3302, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1618, '2025', 1, 3303, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1619, '2025', 1, 3304, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1620, '2025', 1, 3305, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1621, '2025', 1, 3306, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1622, '2025', 1, 3307, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:16', NULL),
(1623, '2025', 1, 3308, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1624, '2025', 1, 3309, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1625, '2025', 1, 3310, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1626, '2025', 1, 3311, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1627, '2025', 1, 3312, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1628, '2025', 1, 3313, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1629, '2025', 1, 3314, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1630, '2025', 1, 3315, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1631, '2025', 1, 3316, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1632, '2025', 1, 3317, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1633, '2025', 1, 3318, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1634, '2025', 1, 3319, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1635, '2025', 1, 3320, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1636, '2025', 1, 3321, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1637, '2025', 1, 3322, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1638, '2025', 1, 3323, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1639, '2025', 1, 3324, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1640, '2025', 1, 3325, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1641, '2025', 1, 3326, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1642, '2025', 1, 3327, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1643, '2025', 1, 3328, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1644, '2025', 1, 3329, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1645, '2025', 1, 3330, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1646, '2025', 1, 3331, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1647, '2025', 1, 3332, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1648, '2025', 1, 3333, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1649, '2025', 1, 3334, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1650, '2025', 1, 3335, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1651, '2025', 1, 3336, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1652, '2025', 1, 3337, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1653, '2025', 1, 3338, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1654, '2025', 1, 3339, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1655, '2025', 1, 3340, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1656, '2025', 1, 3341, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1657, '2025', 1, 3342, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1658, '2025', 1, 3343, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1659, '2025', 1, 3344, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1660, '2025', 1, 3345, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1661, '2025', 1, 3346, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1662, '2025', 1, 3347, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1663, '2025', 1, 3348, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1664, '2025', 1, 3349, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:17', NULL),
(1665, '2025', 1, 3350, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1666, '2025', 1, 3351, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1667, '2025', 1, 3352, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1668, '2025', 1, 3353, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1669, '2025', 1, 3354, 10, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1670, '2025', 1, 3355, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1671, '2025', 1, 3356, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1672, '2025', 1, 3357, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1673, '2025', 1, 3358, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1674, '2025', 1, 3359, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1675, '2025', 1, 3360, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1676, '2025', 1, 3361, 11, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1677, '2025', 1, 3362, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1678, '2025', 1, 3363, 12, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1679, '2025', 1, 3364, 13, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1680, '2025', 1, 3365, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1681, '2025', 1, 3366, 14, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1682, '2025', 1, 3367, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1683, '2025', 1, 3368, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL),
(1684, '2025', 1, 3369, 1, '2026-02-28', NULL, 3, NULL, 1, 1, NULL, '2026-02-28 21:12:18', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_enrollment_codes`
--

CREATE TABLE `student_enrollment_codes` (
  `id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `type` varchar(4) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_code` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_enrollment_codes`
--

INSERT INTO `student_enrollment_codes` (`id`, `syear`, `title`, `short_name`, `type`, `default_code`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, '2025', 'Départ', 'DEP', 'Drop', NULL, '1', '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(2, '2025', 'Expulsé', 'EXP', 'Drop', NULL, '2', '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(3, '2025', 'Début d\'année', 'DEB', 'Add', 'Y', '3', '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(4, '2025', 'Autre district', 'AUTR', 'Add', NULL, '4', '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(5, '2025', 'Transfert', 'TRAN', 'Drop', NULL, '5', '2025-10-05 12:01:17', '2025-10-05 12:01:29'),
(6, '2025', 'Transfert', 'MAN', 'Add', NULL, '6', '2025-10-05 12:01:17', '2025-10-05 12:01:29');

-- --------------------------------------------------------

--
-- Table structure for table `student_field_categories`
--

CREATE TABLE `student_field_categories` (
  `id` int NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `columns` decimal(4,0) DEFAULT NULL,
  `include` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_field_categories`
--

INSERT INTO `student_field_categories` (`id`, `title`, `sort_order`, `columns`, `include`, `created_at`, `updated_at`) VALUES
(1, 'General Info|fr_FR.utf8:Infos générales', '1', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(2, 'Medical|fr_FR.utf8:Médical', NULL, NULL, NULL, '2025-10-05 12:01:17', '2026-02-22 15:42:31'),
(3, 'Addresses & Contacts|fr_FR.utf8:Adresses et contacts', '2', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(4, 'Comments|fr_FR.utf8:Commentaires', '4', NULL, NULL, '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
(5, 'Food Service|fr_FR.utf8:Cantine', NULL, NULL, 'Food_Service/Student', '2025-10-05 12:01:17', '2026-02-22 16:05:03'),
(6, '|ar_AE.utf8:الولي|fr_FR.utf8:Parent|en_US.utf8:Parent', '6', '2', NULL, '2026-02-22 15:31:35', '2026-02-22 15:35:20');

-- --------------------------------------------------------

--
-- Table structure for table `student_medical`
--

CREATE TABLE `student_medical` (
  `id` int NOT NULL,
  `student_id` int NOT NULL,
  `type` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `medical_date` date DEFAULT NULL,
  `comments` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_medical_alerts`
--

CREATE TABLE `student_medical_alerts` (
  `id` int NOT NULL,
  `student_id` int NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_medical_visits`
--

CREATE TABLE `student_medical_visits` (
  `id` int NOT NULL,
  `student_id` int NOT NULL,
  `school_date` date NOT NULL,
  `time_in` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `time_out` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `reason` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `result` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_mp_comments`
--

CREATE TABLE `student_mp_comments` (
  `student_id` int NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `marking_period_id` int NOT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_mp_stats`
--

CREATE TABLE `student_mp_stats` (
  `student_id` int NOT NULL,
  `marking_period_id` int NOT NULL,
  `cum_weighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_unweighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_rank` int DEFAULT NULL,
  `mp_rank` int DEFAULT NULL,
  `class_size` int DEFAULT NULL,
  `sum_weighted_factors` decimal(22,16) DEFAULT NULL,
  `sum_unweighted_factors` decimal(22,16) DEFAULT NULL,
  `count_weighted_factors` int DEFAULT NULL,
  `count_unweighted_factors` int DEFAULT NULL,
  `grade_level_short` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `cr_weighted_factors` decimal(22,16) DEFAULT NULL,
  `cr_unweighted_factors` decimal(22,16) DEFAULT NULL,
  `count_cr_factors` int DEFAULT NULL,
  `cum_cr_weighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_cr_unweighted_factor` decimal(22,16) DEFAULT NULL,
  `credit_attempted` decimal(22,16) DEFAULT NULL,
  `credit_earned` decimal(22,16) DEFAULT NULL,
  `gp_credits` decimal(22,16) DEFAULT NULL,
  `cr_credits` decimal(22,16) DEFAULT NULL,
  `comments` varchar(75) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_report_card_comments`
--

CREATE TABLE `student_report_card_comments` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `student_id` int NOT NULL,
  `course_period_id` int NOT NULL,
  `report_card_comment_id` int NOT NULL,
  `comment` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `marking_period_id` int NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_report_card_grades`
--

CREATE TABLE `student_report_card_grades` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int NOT NULL,
  `student_id` int NOT NULL,
  `course_period_id` int DEFAULT NULL,
  `report_card_grade_id` int DEFAULT NULL,
  `report_card_comment_id` int DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `grade_percent` decimal(4,1) DEFAULT NULL,
  `marking_period_id` int NOT NULL,
  `grade_letter` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `weighted_gp` decimal(7,2) DEFAULT NULL,
  `unweighted_gp` decimal(7,2) DEFAULT NULL,
  `gp_scale` decimal(7,2) DEFAULT NULL,
  `credit_attempted` decimal(22,16) DEFAULT NULL,
  `credit_earned` decimal(22,16) DEFAULT NULL,
  `credit_category` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `id` int NOT NULL,
  `school` text COLLATE utf8mb4_unicode_520_ci,
  `class_rank` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `credit_hours` decimal(6,2) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Triggers `student_report_card_grades`
--
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_delete` AFTER DELETE ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(OLD.student_id, OLD.marking_period_id)
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_insert` AFTER INSERT ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(NEW.student_id, NEW.marking_period_id)
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_update` AFTER UPDATE ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(NEW.student_id, NEW.marking_period_id)
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `table_criteria`
--

CREATE TABLE `table_criteria` (
  `id_criteria` int NOT NULL,
  `key` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `value` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `table_criteria`
--

INSERT INTO `table_criteria` (`id_criteria`, `key`, `value`) VALUES
(1, 'BILSAFHA', 'بالصفحة'),
(2, 'BILTHUMN', 'بالثمن');

-- --------------------------------------------------------

--
-- Table structure for table `table_evaluation`
--

CREATE TABLE `table_evaluation` (
  `id_evaluation` int NOT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `id_score` int DEFAULT NULL,
  `id_criteria` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `table_performance`
--

CREATE TABLE `table_performance` (
  `id_performance` int NOT NULL,
  `date_performance` datetime DEFAULT NULL,
  `from_eya` int DEFAULT NULL,
  `to_eya` int DEFAULT NULL,
  `id_sura` int DEFAULT NULL,
  `has_learned` tinyint(1) DEFAULT NULL,
  `id_evaluation` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `table_score`
--

CREATE TABLE `table_score` (
  `id_score` int NOT NULL,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `value` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `table_score`
--

INSERT INTO `table_score` (`id_score`, `key`, `value`) VALUES
(1, 'EXCELLENT', '{\"دون تنبيهات\": \"ممتاز\"}'),
(2, 'VERY_GOOD', '{\"تنبيه واحد\": \"جيّد جدا\"}'),
(3, 'GOOD', '{\"تنبيهان\": \"جيّد\"}'),
(4, 'FAIL', '{\"أكثر من تنبيهين\": \"يعيد التسميع\"}');

-- --------------------------------------------------------

--
-- Table structure for table `table_speech`
--

CREATE TABLE `table_speech` (
  `id_speech` int NOT NULL,
  `key` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `value` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `max_num_value` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `table_speech`
--

INSERT INTO `table_speech` (`id_speech`, `key`, `value`, `max_num_value`) VALUES
(1, 'TANBIHAT', 'التنبيهات', 6),
(2, 'GHUNNA', 'الغنة', 6),
(3, 'MADUD', 'المدود', 6),
(4, 'QALQALA', 'القلقلة', 6);

-- --------------------------------------------------------

--
-- Table structure for table `table_sura`
--

CREATE TABLE `table_sura` (
  `id_sura` int NOT NULL,
  `key` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `value` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `table_sura`
--

INSERT INTO `table_sura` (`id_sura`, `key`, `value`) VALUES
(1, 'AL_FATIHA', 'الفاتحة'),
(2, 'AL_BAQARA', 'البقرة'),
(3, 'ALI_IMRAN', 'آل عمران'),
(4, 'AN_NISA', 'النساء'),
(5, 'AL_MAIDA', 'المائدة'),
(6, 'AL_ANAM', 'الأنعام'),
(7, 'AL_ARAF', 'الأعراف'),
(8, 'AL_ANFAL', 'الأنفال'),
(9, 'AT_TAWBA', 'التوبة'),
(10, 'YUNUS', 'يونس'),
(11, 'HUD', 'هود'),
(12, 'YUSUF', 'يوسف'),
(13, 'AR_RAD', 'الرعد'),
(14, 'IBRAHIM', 'إبراهيم'),
(15, 'AL_HIJR', 'الحجر'),
(16, 'AN_NAHL', 'النحل'),
(17, 'AL_ISRA', 'الإسراء'),
(18, 'AL_KAHF', 'الكهف'),
(19, 'MARYAM', 'مريم'),
(20, 'TA_HA', 'طه'),
(21, 'AL_ANBIYA', 'الأنبياء'),
(22, 'AL_HAJJ', 'الحج'),
(23, 'AL_MUMINUN', 'المؤمنون'),
(24, 'AN_NUR', 'النور'),
(25, 'AL_FURQAN', 'الفرقان'),
(26, 'ASH_SHUARA', 'الشعراء'),
(27, 'AN_NAML', 'النمل'),
(28, 'AL_QASAS', 'القصص'),
(29, 'AL_ANKABUT', 'العنكبوت'),
(30, 'AR_RUM', 'الروم'),
(31, 'LUQMAN', 'لقمان'),
(32, 'AS_SAJDA', 'السجدة'),
(33, 'AL_AHZAB', 'الأحزاب'),
(34, 'SABA', 'سبإ'),
(35, 'FATIR', 'فاطر'),
(36, 'YA_SIN', 'يس'),
(37, 'AS_SAFFAT', 'الصافات'),
(38, 'SAD', 'ص'),
(39, 'AZ_ZUMAR', 'الزمر'),
(40, 'GHAFIR', 'غافر'),
(41, 'FUSSILAT', 'فصلت'),
(42, 'ASH_SHURA', 'الشورى'),
(43, 'AZ_ZUKHRUF', 'الزخرف'),
(44, 'AD_DUKHAN', 'الدخان'),
(45, 'AL_JATHIYA', 'الجاثية'),
(46, 'AL_AHQAF', 'الأحقاف'),
(47, 'MUHAMMAD', 'محمد'),
(48, 'AL_FATH', 'الفتح'),
(49, 'AL_HUJURAT', 'الحجرات'),
(50, 'QAF', 'ق'),
(51, 'ADH_DHARIYAT', 'الذاريات'),
(52, 'AT_TUR', 'الطور'),
(53, 'AN_NAJM', 'النجم'),
(54, 'AL_QAMAR', 'القمر'),
(55, 'AR_RAHMAN', 'الرحمن'),
(56, 'AL_WAQIA', 'الواقعة'),
(57, 'AL_HADID', 'الحديد'),
(58, 'AL_MUJADILA', 'المجادلة'),
(59, 'AL_HASHR', 'الحشر'),
(60, 'AL_MUMTAHINA', 'الممتحنة'),
(61, 'AS_SAFF', 'الصف'),
(62, 'AL_JUMUA', 'الجمعة'),
(63, 'AL_MUNAFIQUN', 'المنافقون'),
(64, 'AT_TAGHABUN', 'التغابن'),
(65, 'AT_TALAQ', 'الطلاق'),
(66, 'AT_TAHRIM', 'التحريم'),
(67, 'AL_MULK', 'الملك'),
(68, 'AL_QALAM', 'القلم'),
(69, 'AL_HAAQQA', 'الحاقة'),
(70, 'AL_MAARIJ', 'المعارج'),
(71, 'NUH', 'نوح'),
(72, 'AL_JINN', 'الجن'),
(73, 'AL_MUZZAMMIL', 'المزمل'),
(74, 'AL_MUDDATHIR', 'المدثر'),
(75, 'AL_QIYAMA', 'القيامة'),
(76, 'AL_INSAN', 'الإنسان'),
(77, 'AL_MURSALAT', 'المرسلات'),
(78, 'AN_NABA', 'النبإ'),
(79, 'AN_NAZIAT', 'النازعات'),
(80, 'ABASA', 'عبس'),
(81, 'AT_TAKWIR', 'التكوير'),
(82, 'AL_INFITAR', 'الإنفطار'),
(83, 'AL_MUTAFFIFIN', 'المطففين'),
(84, 'AL_INSHIQAQ', 'الإنشقاق'),
(85, 'AL_BURUJ', 'البروج'),
(86, 'AT_TARIQ', 'الطارق'),
(87, 'AL_AALA', 'الأعلى'),
(88, 'AL_GHASHIYA', 'الغاشية'),
(89, 'AL_FAJR', 'الفجر'),
(90, 'AL_BALAD', 'البلد'),
(91, 'ASH_SHAMS', 'الشمس'),
(92, 'AL_LAIL', 'الليل'),
(93, 'AD_DUHA', 'الضحى'),
(94, 'ASH_SHARH', 'الشرح'),
(95, 'AT_TIN', 'التين'),
(96, 'AL_ALAQ', 'العلق'),
(97, 'AL_QADR', 'القدر'),
(98, 'AL_BAYYINA', 'البينة'),
(99, 'AZ_ZALZALA', 'الزلزلة'),
(100, 'AL_ADIYAT', 'العاديات'),
(101, 'AL_QARIA', 'القارعة'),
(102, 'AT_TAKATHUR', 'التكاثر'),
(103, 'AL_ASR', 'العصر'),
(104, 'AL_HUMAZA', 'الهمزة'),
(105, 'AL_FIL', 'الفيل'),
(106, 'QURAISH', 'قريش'),
(107, 'AL_MAUN', 'الماعون'),
(108, 'AL_KAWTHAR', 'الكوثر'),
(109, 'AL_KAFIRUN', 'الكافرون'),
(110, 'AN_NASR', 'النصر'),
(111, 'AL_MASAD', 'المسد'),
(112, 'AL_IKHLAS', 'الإخلاص'),
(113, 'AL_FALAQ', 'الفلق'),
(114, 'AN_NAS', 'الناس');

-- --------------------------------------------------------

--
-- Table structure for table `templates`
--

CREATE TABLE `templates` (
  `modname` varchar(150) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `staff_id` int NOT NULL,
  `template` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `templates`
--

INSERT INTO `templates` (`modname`, `staff_id`, `template`, `created_at`, `updated_at`) VALUES
('Custom/CreateParents.php', 0, 'Cher __PARENT_NAME__,\n\nUn compte parent pour l\'école __SCHOOL_ID__ a été créé pour accéder aux informations de l\'école et des élèves suivants :\n__ASSOCIATED_STUDENTS__\n\nVos identifiants :\nNom d\'utilisateur : __USERNAME__\nMot de passe : __PASSWORD__\n\nUn lien vers le site du logiciel de gestion scolaire et les instructions pour y accéder sont disponibles sur le site de l\'école.__BLOCK2__Cher __PARENT_NAME__,\n\nLes élèves suivants ont été associé à votre compte parent dans le logiciel de gestion scolaire:\n__ASSOCIATED_STUDENTS__', '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
('Custom/NotifyParents.php', 0, 'Cher __PARENT_NAME__,\n\nUn compte parent pour l\'école __SCHOOL_ID__ a été créé pour accéder aux informations de l\'école et des élèves suivants :\n__ASSOCIATED_STUDENTS__\n\nVos identifiants :\nNom d\'utilisateur : __USERNAME__\nMot de passe : __PASSWORD__\n\nUn lien vers le site du logiciel de gestion scolaire et les instructions pour y accéder sont disponibles sur le site de l\'école.', '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
('Email/EmailStudents.php', 0, NULL, '2026-02-28 22:14:15', NULL),
('Email/EmailUsers.php', 0, NULL, '2026-02-28 22:14:15', NULL),
('Grades/HonorRoll.php', 0, '<br /><br /><br />\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\"><strong>__SCHOOL_ID__</strong><br /></span><br /><span style=\"font-size: xx-large;\">Nous reconnaissons par la présente<br /><br /></span></div>\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\"><strong>__FIRST_NAME__ __LAST_NAME__</strong><br /><br /></span></div>\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\">qui a obtenu les <br />mentions</span></div>', '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
('Grades/Transcripts.php', 0, '<h2 style=\"text-align: center;\">Certificat d\'Études</h2>\n<p>Le recteur et le secrétariat certifient :</p>\n<p>Que __FIRST_NAME__ __LAST_NAME__ identifié avec le numéro __SSECURITY__ a suivi les études dans cet établissement correspondant au niveau __GRADE_ID__ pour l\'année __YEAR__ et a obtenu les notes ici mentionnées.</p>\n<p>L\'élève est promu au niveau __NEXT_GRADE_ID__.</p>\n<p>__BLOCK2__</p>\n<p>&nbsp;</p>\n<table style=\"border-collapse: collapse; width: 100%;\" border=\"0\" cellpadding=\"10\"><tbody><tr>\n<td style=\"width: 50%; text-align: center;\"><hr />\n<p>Signature</p>\n<p>&nbsp;</p><hr />\n<p>Titre</p></td>\n<td style=\"width: 50%; text-align: center;\"><hr />\n<p>Signature</p>\n<p>&nbsp;</p><hr />\n<p>Titre</p></td></tr></tbody></table>', '2025-10-05 12:01:17', '2025-10-05 12:01:30'),
('Student_ID_Card/StudentIDCard.php', 0, '<h3>__FULL_NAME__</h3>\r\n<p>Born: __STUDENT_200000004__</p>\r\n<p>Grade Level: __GRADE_ID__</p>\r\n<p>School Year: __SCHOOL_YEAR__</p>', '2025-10-05 13:48:39', NULL),
('Students/Letters.php', 0, '<p></p>', '2025-10-05 12:01:17', NULL);

-- --------------------------------------------------------

--
-- Stand-in structure for view `transcript_grades`
-- (See below for the actual view)
--
CREATE TABLE `transcript_grades` (
`syear` decimal(4,0)
,`school_id` int
,`marking_period_id` int
,`mp_type` varchar(20)
,`short_name` varchar(10)
,`parent_id` bigint
,`grandparent_id` bigint
,`parent_end_date` date
,`end_date` date
,`student_id` int
,`cum_weighted_gpa` decimal(32,19)
,`cum_unweighted_gpa` decimal(32,19)
,`cum_rank` int
,`mp_rank` int
,`class_size` int
,`weighted_gpa` decimal(36,23)
,`unweighted_gpa` decimal(36,23)
,`grade_level_short` varchar(3)
,`comment` text
,`grade_percent` decimal(4,1)
,`grade_letter` varchar(5)
,`weighted_gp` decimal(7,2)
,`unweighted_gp` decimal(7,2)
,`gp_scale` decimal(7,2)
,`credit_attempted` decimal(22,16)
,`credit_earned` decimal(22,16)
,`course_title` text
,`school_name` text
,`school_scale` decimal(10,3)
,`cr_weighted_gpa` decimal(36,23)
,`cr_unweighted_gpa` decimal(36,23)
,`cum_cr_weighted_gpa` decimal(32,19)
,`cum_cr_unweighted_gpa` decimal(32,19)
,`class_rank` varchar(1)
,`comments` varchar(75)
,`credit_hours` decimal(6,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `user_profiles`
--

CREATE TABLE `user_profiles` (
  `id` int NOT NULL,
  `profile` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `user_profiles`
--

INSERT INTO `user_profiles` (`id`, `profile`, `title`, `created_at`, `updated_at`) VALUES
(0, 'student', 'Student', '2025-10-05 12:01:17', NULL),
(1, 'admin', 'Administrator', '2025-10-05 12:01:17', NULL),
(2, 'teacher', 'Teacher', '2025-10-05 12:01:17', NULL),
(3, 'parent', 'Parent', '2025-10-05 12:01:17', NULL);

-- --------------------------------------------------------

--
-- Structure for view `course_details`
--
DROP TABLE IF EXISTS `course_details`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`localhost` SQL SECURITY DEFINER VIEW `course_details`  AS  select `cp`.`school_id` AS `school_id`,`cp`.`syear` AS `syear`,`cp`.`marking_period_id` AS `marking_period_id`,`c`.`subject_id` AS `subject_id`,`cp`.`course_id` AS `course_id`,`cp`.`course_period_id` AS `course_period_id`,`cp`.`teacher_id` AS `teacher_id`,`c`.`title` AS `course_title`,`cp`.`title` AS `cp_title`,`cp`.`grade_scale_id` AS `grade_scale_id`,`cp`.`mp` AS `mp`,`cp`.`credits` AS `credits` from (`course_periods` `cp` join `courses` `c`) where (`cp`.`course_id` = `c`.`course_id`) ;

-- --------------------------------------------------------

--
-- Structure for view `enroll_grade`
--
DROP TABLE IF EXISTS `enroll_grade`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`localhost` SQL SECURITY DEFINER VIEW `enroll_grade`  AS  select `e`.`id` AS `id`,`e`.`syear` AS `syear`,`e`.`school_id` AS `school_id`,`e`.`student_id` AS `student_id`,`e`.`start_date` AS `start_date`,`e`.`end_date` AS `end_date`,`sg`.`short_name` AS `short_name`,`sg`.`title` AS `title` from (`student_enrollment` `e` join `school_gradelevels` `sg`) where (`e`.`grade_id` = `sg`.`id`) ;

-- --------------------------------------------------------

--
-- Structure for view `marking_periods`
--
DROP TABLE IF EXISTS `marking_periods`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`localhost` SQL SECURITY DEFINER VIEW `marking_periods`  AS  select `school_marking_periods`.`marking_period_id` AS `marking_period_id`,'Rosario' AS `mp_source`,`school_marking_periods`.`syear` AS `syear`,`school_marking_periods`.`school_id` AS `school_id`,(case when (`school_marking_periods`.`mp` = 'FY') then 'year' when (`school_marking_periods`.`mp` = 'SEM') then 'semester' when (`school_marking_periods`.`mp` = 'QTR') then 'quarter' else NULL end) AS `mp_type`,`school_marking_periods`.`title` AS `title`,`school_marking_periods`.`short_name` AS `short_name`,`school_marking_periods`.`sort_order` AS `sort_order`,(case when (`school_marking_periods`.`parent_id` > 0) then `school_marking_periods`.`parent_id` else -(1) end) AS `parent_id`,(case when ((select `smp`.`parent_id` from `school_marking_periods` `smp` where (`smp`.`marking_period_id` = `school_marking_periods`.`parent_id`)) > 0) then (select `smp`.`parent_id` from `school_marking_periods` `smp` where (`smp`.`marking_period_id` = `school_marking_periods`.`parent_id`)) else -(1) end) AS `grandparent_id`,`school_marking_periods`.`start_date` AS `start_date`,`school_marking_periods`.`end_date` AS `end_date`,`school_marking_periods`.`post_start_date` AS `post_start_date`,`school_marking_periods`.`post_end_date` AS `post_end_date`,`school_marking_periods`.`does_grades` AS `does_grades`,`school_marking_periods`.`does_comments` AS `does_comments` from `school_marking_periods` union select `history_marking_periods`.`marking_period_id` AS `marking_period_id`,'History' AS `mp_source`,`history_marking_periods`.`syear` AS `syear`,`history_marking_periods`.`school_id` AS `school_id`,`history_marking_periods`.`mp_type` AS `mp_type`,`history_marking_periods`.`name` AS `title`,`history_marking_periods`.`short_name` AS `short_name`,NULL AS `sort_order`,`history_marking_periods`.`parent_id` AS `parent_id`,-(1) AS `grandparent_id`,NULL AS `start_date`,`history_marking_periods`.`post_end_date` AS `end_date`,NULL AS `post_start_date`,`history_marking_periods`.`post_end_date` AS `post_end_date`,'Y' AS `does_grades`,NULL AS `does_comments` from `history_marking_periods` ;

-- --------------------------------------------------------

--
-- Structure for view `transcript_grades`
--
DROP TABLE IF EXISTS `transcript_grades`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`localhost` SQL SECURITY DEFINER VIEW `transcript_grades`  AS  select `mp`.`syear` AS `syear`,`mp`.`school_id` AS `school_id`,`mp`.`marking_period_id` AS `marking_period_id`,`mp`.`mp_type` AS `mp_type`,`mp`.`short_name` AS `short_name`,`mp`.`parent_id` AS `parent_id`,`mp`.`grandparent_id` AS `grandparent_id`,(select `mp2`.`end_date` from (`student_report_card_grades` join `marking_periods` `mp2` on((`mp2`.`marking_period_id` = `student_report_card_grades`.`marking_period_id`))) where ((`student_report_card_grades`.`student_id` = `sms`.`student_id`) and ((`student_report_card_grades`.`marking_period_id` = `mp`.`parent_id`) or (`student_report_card_grades`.`marking_period_id` = `mp`.`grandparent_id`)) and (`student_report_card_grades`.`course_title` = `srcg`.`course_title`)) order by `mp2`.`end_date` limit 1) AS `parent_end_date`,`mp`.`end_date` AS `end_date`,`sms`.`student_id` AS `student_id`,(`sms`.`cum_weighted_factor` * coalesce(`schools`.`reporting_gp_scale`,(select `schools`.`reporting_gp_scale` from `schools` where (`mp`.`school_id` = `schools`.`id`) order by `schools`.`syear` limit 1))) AS `cum_weighted_gpa`,(`sms`.`cum_unweighted_factor` * `schools`.`reporting_gp_scale`) AS `cum_unweighted_gpa`,`sms`.`cum_rank` AS `cum_rank`,`sms`.`mp_rank` AS `mp_rank`,`sms`.`class_size` AS `class_size`,((`sms`.`sum_weighted_factors` / `sms`.`count_weighted_factors`) * `schools`.`reporting_gp_scale`) AS `weighted_gpa`,((`sms`.`sum_unweighted_factors` / `sms`.`count_unweighted_factors`) * `schools`.`reporting_gp_scale`) AS `unweighted_gpa`,`sms`.`grade_level_short` AS `grade_level_short`,`srcg`.`comment` AS `comment`,`srcg`.`grade_percent` AS `grade_percent`,`srcg`.`grade_letter` AS `grade_letter`,`srcg`.`weighted_gp` AS `weighted_gp`,`srcg`.`unweighted_gp` AS `unweighted_gp`,`srcg`.`gp_scale` AS `gp_scale`,`srcg`.`credit_attempted` AS `credit_attempted`,`srcg`.`credit_earned` AS `credit_earned`,`srcg`.`course_title` AS `course_title`,`srcg`.`school` AS `school_name`,`schools`.`reporting_gp_scale` AS `school_scale`,((`sms`.`cr_weighted_factors` / `sms`.`count_cr_factors`) * `schools`.`reporting_gp_scale`) AS `cr_weighted_gpa`,((`sms`.`cr_unweighted_factors` / `sms`.`count_cr_factors`) * `schools`.`reporting_gp_scale`) AS `cr_unweighted_gpa`,(`sms`.`cum_cr_weighted_factor` * `schools`.`reporting_gp_scale`) AS `cum_cr_weighted_gpa`,(`sms`.`cum_cr_unweighted_factor` * `schools`.`reporting_gp_scale`) AS `cum_cr_unweighted_gpa`,`srcg`.`class_rank` AS `class_rank`,`sms`.`comments` AS `comments`,`srcg`.`credit_hours` AS `credit_hours` from (((`marking_periods` `mp` join `student_report_card_grades` `srcg` on((`mp`.`marking_period_id` = `srcg`.`marking_period_id`))) join `student_mp_stats` `sms` on(((`sms`.`marking_period_id` = `mp`.`marking_period_id`) and (`sms`.`student_id` = `srcg`.`student_id`)))) left join `schools` on(((`mp`.`school_id` = `schools`.`id`) and (`mp`.`syear` = `schools`.`syear`)))) order by `srcg`.`course_period_id` ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `accounting_categories`
--
ALTER TABLE `accounting_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `accounting_payments_ind1` (`staff_id`),
  ADD KEY `accounting_payments_ind2` (`amount`);

--
-- Indexes for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  ADD PRIMARY KEY (`id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `address`
--
ALTER TABLE `address`
  ADD PRIMARY KEY (`address_id`),
  ADD KEY `address_3` (`zipcode`),
  ADD KEY `address_4` (`street`);

--
-- Indexes for table `address_fields`
--
ALTER TABLE `address_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `address_desc_ind2` (`type`),
  ADD KEY `address_fields_ind3` (`category_id`);

--
-- Indexes for table `address_field_categories`
--
ALTER TABLE `address_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `attendance_calendar`
--
ALTER TABLE `attendance_calendar`
  ADD PRIMARY KEY (`syear`,`school_id`,`school_date`,`calendar_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  ADD PRIMARY KEY (`calendar_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `attendance_codes_ind3` (`short_name`);

--
-- Indexes for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_completed`
--
ALTER TABLE `attendance_completed`
  ADD PRIMARY KEY (`staff_id`,`school_date`,`period_id`,`table_name`);

--
-- Indexes for table `attendance_day`
--
ALTER TABLE `attendance_day`
  ADD PRIMARY KEY (`student_id`,`school_date`),
  ADD KEY `marking_period_id` (`marking_period_id`);

--
-- Indexes for table `attendance_period`
--
ALTER TABLE `attendance_period`
  ADD PRIMARY KEY (`student_id`,`school_date`,`period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `attendance_period_ind1` (`student_id`),
  ADD KEY `attendance_period_ind2` (`period_id`),
  ADD KEY `attendance_period_ind4` (`school_date`),
  ADD KEY `attendance_period_ind5` (`attendance_code`);

--
-- Indexes for table `billing_fees`
--
ALTER TABLE `billing_fees`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `billing_payments`
--
ALTER TABLE `billing_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `billing_payments_ind2` (`amount`),
  ADD KEY `billing_payments_ind3` (`refunded_payment_id`);

--
-- Indexes for table `calendar_events`
--
ALTER TABLE `calendar_events`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`course_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `courses_ind2` (`subject_id`);

--
-- Indexes for table `course_periods`
--
ALTER TABLE `course_periods`
  ADD PRIMARY KEY (`course_period_id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `teacher_id` (`teacher_id`),
  ADD KEY `secondary_teacher_id` (`secondary_teacher_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  ADD PRIMARY KEY (`course_period_school_periods_id`),
  ADD UNIQUE KEY `course_period_id` (`course_period_id`,`period_id`);

--
-- Indexes for table `course_subjects`
--
ALTER TABLE `course_subjects`
  ADD PRIMARY KEY (`subject_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `csp_reports`
--
ALTER TABLE `csp_reports`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `custom_fields`
--
ALTER TABLE `custom_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `custom_desc_ind2` (`type`),
  ADD KEY `custom_fields_ind3` (`category_id`);

--
-- Indexes for table `discipline_fields`
--
ALTER TABLE `discipline_fields`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `eligibility`
--
ALTER TABLE `eligibility`
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `eligibility_ind1` (`student_id`,`course_period_id`,`school_date`);

--
-- Indexes for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `eligibility_completed`
--
ALTER TABLE `eligibility_completed`
  ADD PRIMARY KEY (`staff_id`,`school_date`,`period_id`);

--
-- Indexes for table `food_service_accounts`
--
ALTER TABLE `food_service_accounts`
  ADD PRIMARY KEY (`account_id`);

--
-- Indexes for table `food_service_categories`
--
ALTER TABLE `food_service_categories`
  ADD PRIMARY KEY (`category_id`),
  ADD UNIQUE KEY `food_service_categories_title` (`school_id`,`menu_id`,`title`);

--
-- Indexes for table `food_service_items`
--
ALTER TABLE `food_service_items`
  ADD PRIMARY KEY (`item_id`),
  ADD UNIQUE KEY `food_service_items_short_name` (`school_id`,`short_name`);

--
-- Indexes for table `food_service_menus`
--
ALTER TABLE `food_service_menus`
  ADD PRIMARY KEY (`menu_id`),
  ADD UNIQUE KEY `food_service_menus_title` (`school_id`,`title`);

--
-- Indexes for table `food_service_menu_items`
--
ALTER TABLE `food_service_menu_items`
  ADD PRIMARY KEY (`menu_item_id`);

--
-- Indexes for table `food_service_staff_accounts`
--
ALTER TABLE `food_service_staff_accounts`
  ADD PRIMARY KEY (`staff_id`),
  ADD UNIQUE KEY `barcode` (`barcode`);

--
-- Indexes for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  ADD PRIMARY KEY (`transaction_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `food_service_staff_transaction_items`
--
ALTER TABLE `food_service_staff_transaction_items`
  ADD PRIMARY KEY (`item_id`,`transaction_id`),
  ADD KEY `transaction_id` (`transaction_id`);

--
-- Indexes for table `food_service_student_accounts`
--
ALTER TABLE `food_service_student_accounts`
  ADD PRIMARY KEY (`student_id`),
  ADD UNIQUE KEY `barcode` (`barcode`);

--
-- Indexes for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  ADD PRIMARY KEY (`transaction_id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `food_service_transaction_items`
--
ALTER TABLE `food_service_transaction_items`
  ADD PRIMARY KEY (`item_id`,`transaction_id`),
  ADD KEY `transaction_id` (`transaction_id`);

--
-- Indexes for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  ADD PRIMARY KEY (`assignment_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `gradebook_assignments_ind3` (`assignment_type_id`);

--
-- Indexes for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  ADD PRIMARY KEY (`assignment_type_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `course_id` (`course_id`);

--
-- Indexes for table `gradebook_grades`
--
ALTER TABLE `gradebook_grades`
  ADD PRIMARY KEY (`student_id`,`assignment_id`,`course_period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `gradebook_grades_ind1` (`assignment_id`);

--
-- Indexes for table `grades_completed`
--
ALTER TABLE `grades_completed`
  ADD PRIMARY KEY (`staff_id`,`marking_period_id`,`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `course_period_id` (`course_period_id`);

--
-- Indexes for table `history_marking_periods`
--
ALTER TABLE `history_marking_periods`
  ADD PRIMARY KEY (`marking_period_id`),
  ADD KEY `history_marking_period_ind1` (`school_id`),
  ADD KEY `history_marking_period_ind2` (`syear`);

--
-- Indexes for table `lunch_period`
--
ALTER TABLE `lunch_period`
  ADD PRIMARY KEY (`student_id`,`school_date`,`period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `lunch_period_ind2` (`period_id`),
  ADD KEY `lunch_period_ind3` (`attendance_code`),
  ADD KEY `lunch_period_ind4` (`school_date`);

--
-- Indexes for table `moodlexrosario`
--
ALTER TABLE `moodlexrosario`
  ADD PRIMARY KEY (`column`,`rosario_id`);

--
-- Indexes for table `people`
--
ALTER TABLE `people`
  ADD PRIMARY KEY (`person_id`),
  ADD KEY `people_1` (`last_name`,`first_name`);

--
-- Indexes for table `people_fields`
--
ALTER TABLE `people_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `people_desc_ind2` (`type`),
  ADD KEY `people_fields_ind3` (`category_id`);

--
-- Indexes for table `people_field_categories`
--
ALTER TABLE `people_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `people_join_contacts`
--
ALTER TABLE `people_join_contacts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `people_join_contacts_ind1` (`person_id`);

--
-- Indexes for table `portal_notes`
--
ALTER TABLE `portal_notes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `portal_polls`
--
ALTER TABLE `portal_polls`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `portal_poll_questions`
--
ALTER TABLE `portal_poll_questions`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `profile_exceptions`
--
ALTER TABLE `profile_exceptions`
  ADD PRIMARY KEY (`profile_id`,`modname`);

--
-- Indexes for table `program_config`
--
ALTER TABLE `program_config`
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `program_user_config`
--
ALTER TABLE `program_user_config`
  ADD KEY `program_user_config_ind1` (`user_id`,`program`);

--
-- Indexes for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_comment_codes`
--
ALTER TABLE `report_card_comment_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `report_card_comment_codes_ind1` (`school_id`);

--
-- Indexes for table `report_card_comment_code_scales`
--
ALTER TABLE `report_card_comment_code_scales`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `resources`
--
ALTER TABLE `resources`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `schedule`
--
ALTER TABLE `schedule`
  ADD KEY `course_id` (`course_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `schedule_ind3` (`student_id`,`marking_period_id`,`start_date`,`end_date`);

--
-- Indexes for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  ADD PRIMARY KEY (`request_id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `schedule_requests_ind1` (`student_id`,`course_id`,`syear`);

--
-- Indexes for table `schools`
--
ALTER TABLE `schools`
  ADD PRIMARY KEY (`id`,`syear`),
  ADD KEY `schools_ind1` (`syear`);

--
-- Indexes for table `school_fields`
--
ALTER TABLE `school_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_desc_ind2` (`type`);

--
-- Indexes for table `school_gradelevels`
--
ALTER TABLE `school_gradelevels`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_gradelevels_ind1` (`school_id`);

--
-- Indexes for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  ADD PRIMARY KEY (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `school_marking_periods_ind1` (`parent_id`),
  ADD KEY `school_marking_periods_ind2` (`syear`,`school_id`,`start_date`,`end_date`);

--
-- Indexes for table `school_periods`
--
ALTER TABLE `school_periods`
  ADD PRIMARY KEY (`period_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `staff`
--
ALTER TABLE `staff`
  ADD PRIMARY KEY (`staff_id`),
  ADD UNIQUE KEY `staff_ind4` (`username`,`syear`),
  ADD KEY `staff_ind1` (`staff_id`,`syear`),
  ADD KEY `staff_ind2` (`last_name`,`first_name`),
  ADD KEY `staff_ind3` (`schools`);

--
-- Indexes for table `staff_exceptions`
--
ALTER TABLE `staff_exceptions`
  ADD PRIMARY KEY (`user_id`,`modname`);

--
-- Indexes for table `staff_fields`
--
ALTER TABLE `staff_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `staff_desc_ind2` (`type`),
  ADD KEY `staff_fields_ind3` (`category_id`);

--
-- Indexes for table `staff_field_categories`
--
ALTER TABLE `staff_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `students`
--
ALTER TABLE `students`
  ADD PRIMARY KEY (`student_id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD KEY `name` (`last_name`,`first_name`,`middle_name`),
  ADD KEY `custom_ind200000012` (`custom_200000012`(255)),
  ADD KEY `custom_ind200000013` (`custom_200000013`(255)),
  ADD KEY `custom_ind200000014` (`custom_200000014`(255)),
  ADD KEY `custom_ind200000015` (`custom_200000015`(255)),
  ADD KEY `custom_ind200000016` (`custom_200000016`(255));

--
-- Indexes for table `students_join_address`
--
ALTER TABLE `students_join_address`
  ADD PRIMARY KEY (`id`),
  ADD KEY `stu_addr_meets_2` (`address_id`),
  ADD KEY `students_join_address_ind1` (`student_id`);

--
-- Indexes for table `students_join_people`
--
ALTER TABLE `students_join_people`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `relations_meets_2` (`address_id`);

--
-- Indexes for table `students_join_users`
--
ALTER TABLE `students_join_users`
  ADD PRIMARY KEY (`student_id`,`staff_id`),
  ADD KEY `staff_id` (`staff_id`);

--
-- Indexes for table `student_assignments`
--
ALTER TABLE `student_assignments`
  ADD PRIMARY KEY (`assignment_id`,`student_id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_eligibility_activities`
--
ALTER TABLE `student_eligibility_activities`
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `student_enrollment_2` (`grade_id`),
  ADD KEY `student_enrollment_4` (`start_date`,`end_date`);

--
-- Indexes for table `student_enrollment_codes`
--
ALTER TABLE `student_enrollment_codes`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_field_categories`
--
ALTER TABLE `student_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_medical`
--
ALTER TABLE `student_medical`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_mp_comments`
--
ALTER TABLE `student_mp_comments`
  ADD PRIMARY KEY (`student_id`,`syear`,`marking_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`);

--
-- Indexes for table `student_mp_stats`
--
ALTER TABLE `student_mp_stats`
  ADD PRIMARY KEY (`student_id`,`marking_period_id`);

--
-- Indexes for table `student_report_card_comments`
--
ALTER TABLE `student_report_card_comments`
  ADD PRIMARY KEY (`syear`,`student_id`,`course_period_id`,`marking_period_id`,`report_card_comment_id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `student_report_card_grades_ind4` (`marking_period_id`);

--
-- Indexes for table `table_criteria`
--
ALTER TABLE `table_criteria`
  ADD PRIMARY KEY (`id_criteria`);

--
-- Indexes for table `table_evaluation`
--
ALTER TABLE `table_evaluation`
  ADD PRIMARY KEY (`id_evaluation`),
  ADD KEY `id_score` (`id_score`),
  ADD KEY `id_criteria` (`id_criteria`);

--
-- Indexes for table `table_performance`
--
ALTER TABLE `table_performance`
  ADD PRIMARY KEY (`id_performance`),
  ADD KEY `id_sura` (`id_sura`),
  ADD KEY `id_evaluation` (`id_evaluation`);

--
-- Indexes for table `table_score`
--
ALTER TABLE `table_score`
  ADD PRIMARY KEY (`id_score`);

--
-- Indexes for table `table_speech`
--
ALTER TABLE `table_speech`
  ADD PRIMARY KEY (`id_speech`);

--
-- Indexes for table `table_sura`
--
ALTER TABLE `table_sura`
  ADD PRIMARY KEY (`id_sura`);

--
-- Indexes for table `templates`
--
ALTER TABLE `templates`
  ADD PRIMARY KEY (`modname`,`staff_id`);

--
-- Indexes for table `user_profiles`
--
ALTER TABLE `user_profiles`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `accounting_categories`
--
ALTER TABLE `accounting_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address`
--
ALTER TABLE `address`
  MODIFY `address_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address_fields`
--
ALTER TABLE `address_fields`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address_field_categories`
--
ALTER TABLE `address_field_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  MODIFY `calendar_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `billing_fees`
--
ALTER TABLE `billing_fees`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `billing_payments`
--
ALTER TABLE `billing_payments`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `calendar_events`
--
ALTER TABLE `calendar_events`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `courses`
--
ALTER TABLE `courses`
  MODIFY `course_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_periods`
--
ALTER TABLE `course_periods`
  MODIFY `course_period_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  MODIFY `course_period_school_periods_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_subjects`
--
ALTER TABLE `course_subjects`
  MODIFY `subject_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `csp_reports`
--
ALTER TABLE `csp_reports`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `custom_fields`
--
ALTER TABLE `custom_fields`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=200000017;

--
-- AUTO_INCREMENT for table `discipline_fields`
--
ALTER TABLE `discipline_fields`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `food_service_categories`
--
ALTER TABLE `food_service_categories`
  MODIFY `category_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `food_service_items`
--
ALTER TABLE `food_service_items`
  MODIFY `item_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `food_service_menus`
--
ALTER TABLE `food_service_menus`
  MODIFY `menu_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `food_service_menu_items`
--
ALTER TABLE `food_service_menu_items`
  MODIFY `menu_item_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  MODIFY `transaction_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  MODIFY `transaction_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  MODIFY `assignment_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  MODIFY `assignment_type_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people`
--
ALTER TABLE `people`
  MODIFY `person_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_fields`
--
ALTER TABLE `people_fields`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_field_categories`
--
ALTER TABLE `people_field_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_join_contacts`
--
ALTER TABLE `people_join_contacts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_notes`
--
ALTER TABLE `portal_notes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_polls`
--
ALTER TABLE `portal_polls`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_poll_questions`
--
ALTER TABLE `portal_poll_questions`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comment_codes`
--
ALTER TABLE `report_card_comment_codes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comment_code_scales`
--
ALTER TABLE `report_card_comment_code_scales`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `resources`
--
ALTER TABLE `resources`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  MODIFY `request_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `schools`
--
ALTER TABLE `schools`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `school_fields`
--
ALTER TABLE `school_fields`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `school_gradelevels`
--
ALTER TABLE `school_gradelevels`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  MODIFY `marking_period_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `school_periods`
--
ALTER TABLE `school_periods`
  MODIFY `period_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `staff`
--
ALTER TABLE `staff`
  MODIFY `staff_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `staff_fields`
--
ALTER TABLE `staff_fields`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=200000002;

--
-- AUTO_INCREMENT for table `staff_field_categories`
--
ALTER TABLE `staff_field_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `students`
--
ALTER TABLE `students`
  MODIFY `student_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3370;

--
-- AUTO_INCREMENT for table `students_join_address`
--
ALTER TABLE `students_join_address`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students_join_people`
--
ALTER TABLE `students_join_people`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=1685;

--
-- AUTO_INCREMENT for table `student_enrollment_codes`
--
ALTER TABLE `student_enrollment_codes`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `student_field_categories`
--
ALTER TABLE `student_field_categories`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `student_medical`
--
ALTER TABLE `student_medical`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  MODIFY `id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `user_profiles`
--
ALTER TABLE `user_profiles`
  MODIFY `id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  ADD CONSTRAINT `accounting_incomes_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `accounting_categories` (`id`),
  ADD CONSTRAINT `accounting_incomes_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  ADD CONSTRAINT `accounting_payments_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `accounting_payments_ibfk_2` FOREIGN KEY (`category_id`) REFERENCES `accounting_categories` (`id`),
  ADD CONSTRAINT `accounting_payments_ibfk_3` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  ADD CONSTRAINT `accounting_salaries_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `accounting_salaries_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_calendar`
--
ALTER TABLE `attendance_calendar`
  ADD CONSTRAINT `attendance_calendar_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  ADD CONSTRAINT `attendance_calendars_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  ADD CONSTRAINT `attendance_codes_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  ADD CONSTRAINT `attendance_code_categories_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_completed`
--
ALTER TABLE `attendance_completed`
  ADD CONSTRAINT `attendance_completed_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `attendance_day`
--
ALTER TABLE `attendance_day`
  ADD CONSTRAINT `attendance_day_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `attendance_day_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `attendance_period`
--
ALTER TABLE `attendance_period`
  ADD CONSTRAINT `attendance_period_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `attendance_period_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `attendance_period_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `billing_fees`
--
ALTER TABLE `billing_fees`
  ADD CONSTRAINT `billing_fees_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `billing_fees_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `billing_payments`
--
ALTER TABLE `billing_payments`
  ADD CONSTRAINT `billing_payments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `billing_payments_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `calendar_events`
--
ALTER TABLE `calendar_events`
  ADD CONSTRAINT `calendar_events_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `courses`
--
ALTER TABLE `courses`
  ADD CONSTRAINT `courses_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `course_periods`
--
ALTER TABLE `course_periods`
  ADD CONSTRAINT `course_periods_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `course_periods_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `course_periods_ibfk_3` FOREIGN KEY (`teacher_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `course_periods_ibfk_4` FOREIGN KEY (`secondary_teacher_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `course_periods_ibfk_5` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  ADD CONSTRAINT `course_period_school_periods_ibfk_1` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `course_subjects`
--
ALTER TABLE `course_subjects`
  ADD CONSTRAINT `course_subjects_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  ADD CONSTRAINT `discipline_field_usage_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  ADD CONSTRAINT `discipline_referrals_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `discipline_referrals_ibfk_2` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `discipline_referrals_ibfk_3` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `eligibility`
--
ALTER TABLE `eligibility`
  ADD CONSTRAINT `eligibility_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `eligibility_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  ADD CONSTRAINT `eligibility_activities_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `eligibility_completed`
--
ALTER TABLE `eligibility_completed`
  ADD CONSTRAINT `eligibility_completed_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `food_service_staff_accounts`
--
ALTER TABLE `food_service_staff_accounts`
  ADD CONSTRAINT `food_service_staff_accounts_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  ADD CONSTRAINT `food_service_staff_transactions_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `food_service_staff_transactions_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `food_service_staff_transaction_items`
--
ALTER TABLE `food_service_staff_transaction_items`
  ADD CONSTRAINT `food_service_staff_transaction_items_ibfk_1` FOREIGN KEY (`transaction_id`) REFERENCES `food_service_staff_transactions` (`transaction_id`);

--
-- Constraints for table `food_service_student_accounts`
--
ALTER TABLE `food_service_student_accounts`
  ADD CONSTRAINT `food_service_student_accounts_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  ADD CONSTRAINT `food_service_transactions_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `food_service_transactions_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `food_service_transaction_items`
--
ALTER TABLE `food_service_transaction_items`
  ADD CONSTRAINT `food_service_transaction_items_ibfk_1` FOREIGN KEY (`transaction_id`) REFERENCES `food_service_transactions` (`transaction_id`);

--
-- Constraints for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  ADD CONSTRAINT `gradebook_assignments_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `gradebook_assignments_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `gradebook_assignments_ibfk_3` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `gradebook_assignments_ibfk_4` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`);

--
-- Constraints for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  ADD CONSTRAINT `gradebook_assignment_types_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `gradebook_assignment_types_ibfk_2` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`);

--
-- Constraints for table `gradebook_grades`
--
ALTER TABLE `gradebook_grades`
  ADD CONSTRAINT `gradebook_grades_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `gradebook_grades_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `grades_completed`
--
ALTER TABLE `grades_completed`
  ADD CONSTRAINT `grades_completed_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `grades_completed_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `grades_completed_ibfk_3` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `lunch_period`
--
ALTER TABLE `lunch_period`
  ADD CONSTRAINT `lunch_period_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `lunch_period_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `lunch_period_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `portal_notes`
--
ALTER TABLE `portal_notes`
  ADD CONSTRAINT `portal_notes_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `portal_polls`
--
ALTER TABLE `portal_polls`
  ADD CONSTRAINT `portal_polls_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `program_config`
--
ALTER TABLE `program_config`
  ADD CONSTRAINT `program_config_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  ADD CONSTRAINT `report_card_comments_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  ADD CONSTRAINT `report_card_comment_categories_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `report_card_comment_categories_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  ADD CONSTRAINT `report_card_grades_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  ADD CONSTRAINT `report_card_grade_scales_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `schedule`
--
ALTER TABLE `schedule`
  ADD CONSTRAINT `schedule_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `schedule_ibfk_2` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `schedule_ibfk_3` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `schedule_ibfk_4` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `schedule_ibfk_5` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  ADD CONSTRAINT `schedule_requests_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `schedule_requests_ibfk_2` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `schedule_requests_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `schedule_requests_ibfk_4` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  ADD CONSTRAINT `school_marking_periods_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `school_periods`
--
ALTER TABLE `school_periods`
  ADD CONSTRAINT `school_periods_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `staff_exceptions`
--
ALTER TABLE `staff_exceptions`
  ADD CONSTRAINT `staff_exceptions_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `students_join_address`
--
ALTER TABLE `students_join_address`
  ADD CONSTRAINT `students_join_address_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `students_join_people`
--
ALTER TABLE `students_join_people`
  ADD CONSTRAINT `students_join_people_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `students_join_users`
--
ALTER TABLE `students_join_users`
  ADD CONSTRAINT `students_join_users_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `students_join_users_ibfk_2` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `student_assignments`
--
ALTER TABLE `student_assignments`
  ADD CONSTRAINT `student_assignments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_eligibility_activities`
--
ALTER TABLE `student_eligibility_activities`
  ADD CONSTRAINT `student_eligibility_activities_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  ADD CONSTRAINT `student_enrollment_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_enrollment_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `student_medical`
--
ALTER TABLE `student_medical`
  ADD CONSTRAINT `student_medical_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  ADD CONSTRAINT `student_medical_alerts_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  ADD CONSTRAINT `student_medical_visits_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_mp_comments`
--
ALTER TABLE `student_mp_comments`
  ADD CONSTRAINT `student_mp_comments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_mp_comments_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `student_mp_stats`
--
ALTER TABLE `student_mp_stats`
  ADD CONSTRAINT `student_mp_stats_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_report_card_comments`
--
ALTER TABLE `student_report_card_comments`
  ADD CONSTRAINT `student_report_card_comments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_report_card_comments_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `student_report_card_comments_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `student_report_card_comments_ibfk_4` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  ADD CONSTRAINT `student_report_card_grades_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_report_card_grades_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `table_evaluation`
--
ALTER TABLE `table_evaluation`
  ADD CONSTRAINT `table_evaluation_ibfk_1` FOREIGN KEY (`id_score`) REFERENCES `table_score` (`id_score`),
  ADD CONSTRAINT `table_evaluation_ibfk_2` FOREIGN KEY (`id_criteria`) REFERENCES `table_criteria` (`id_criteria`);

--
-- Constraints for table `table_performance`
--
ALTER TABLE `table_performance`
  ADD CONSTRAINT `table_performance_ibfk_1` FOREIGN KEY (`id_sura`) REFERENCES `table_sura` (`id_sura`),
  ADD CONSTRAINT `table_performance_ibfk_2` FOREIGN KEY (`id_evaluation`) REFERENCES `table_evaluation` (`id_evaluation`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
