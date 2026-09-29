-- Evora_Police — database schema (Made By LR)
-- The resource creates these tables automatically (Config.Database.AutoCreateTables).
-- Import this file manually only if automatic creation is disabled.

CREATE TABLE IF NOT EXISTS `evora_police_players` (
    `user_id` INT NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `avatar` VARCHAR(255) NOT NULL DEFAULT '',
    `avatar_at` INT NOT NULL DEFAULT 0,
    `last_seen` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_officers` (
    `user_id` INT NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `rank_group` VARCHAR(64) NOT NULL DEFAULT '',
    `sector` VARCHAR(96) NOT NULL DEFAULT '',
    `ministry` VARCHAR(64) NOT NULL DEFAULT '',
    `groups_json` TEXT NULL,
    `military_code` VARCHAR(32) NOT NULL DEFAULT '',
    `attendance_total` INT NOT NULL DEFAULT 0,
    `fines_issued` INT NOT NULL DEFAULT 0,
    `jails_issued` INT NOT NULL DEFAULT 0,
    `reports_handled` INT NOT NULL DEFAULT 0,
    `impounds_issued` INT NOT NULL DEFAULT 0,
    `vacation_balance` INT NOT NULL DEFAULT 0,
    `on_duty` TINYINT NOT NULL DEFAULT 0,
    `duty_started_at` INT NOT NULL DEFAULT 0,
    `duty_last_seen` INT NOT NULL DEFAULT 0,
    `last_clock_in` INT NOT NULL DEFAULT 0,
    `last_clock_out` INT NOT NULL DEFAULT 0,
    `active` TINYINT NOT NULL DEFAULT 1,
    `created_at` INT NOT NULL DEFAULT 0,
    `updated_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`user_id`),
    KEY `idx_sector` (`sector`),
    KEY `idx_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_attendance` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `user_id` INT NOT NULL,
    `sector` VARCHAR(96) NOT NULL DEFAULT '',
    `clock_in` INT NOT NULL,
    `clock_out` INT NOT NULL,
    `duration` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_vacations` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `user_id` INT NOT NULL,
    `days` INT NOT NULL,
    `start_at` INT NOT NULL,
    `end_at` INT NOT NULL,
    `original_groups` TEXT NOT NULL,
    `inactive_group` VARCHAR(64) NOT NULL DEFAULT '',
    `status` VARCHAR(16) NOT NULL DEFAULT 'active',
    `restored` TINYINT NOT NULL DEFAULT 0,
    `ended_at` INT NOT NULL DEFAULT 0,
    `ended_by` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_user_status` (`user_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_pending` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `user_id` INT NOT NULL,
    `action` VARCHAR(16) NOT NULL,
    `group_name` VARCHAR(64) NOT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_reports` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `reporter_id` INT NOT NULL,
    `reporter_name` VARCHAR(64) NOT NULL DEFAULT '',
    `target_id` INT NOT NULL,
    `target_name` VARCHAR(64) NOT NULL DEFAULT '',
    `reason` VARCHAR(255) NOT NULL DEFAULT '',
    `status` VARCHAR(16) NOT NULL DEFAULT 'new',
    `assigned_id` INT NOT NULL DEFAULT 0,
    `assigned_name` VARCHAR(64) NOT NULL DEFAULT '',
    `pos_x` FLOAT NOT NULL DEFAULT 0,
    `pos_y` FLOAT NOT NULL DEFAULT 0,
    `pos_z` FLOAT NOT NULL DEFAULT 0,
    `created_at` INT NOT NULL,
    `updated_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_status` (`status`),
    KEY `idx_reporter` (`reporter_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_wanted` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `target_id` INT NOT NULL,
    `target_name` VARCHAR(64) NOT NULL DEFAULT '',
    `target_job` VARCHAR(64) NOT NULL DEFAULT '',
    `reason` VARCHAR(255) NOT NULL DEFAULT '',
    `created_by_id` INT NOT NULL DEFAULT 0,
    `created_by_name` VARCHAR(64) NOT NULL DEFAULT '',
    `created_at` INT NOT NULL,
    `active` TINYINT NOT NULL DEFAULT 1,
    `cleared_by_id` INT NOT NULL DEFAULT 0,
    `cleared_by_name` VARCHAR(64) NOT NULL DEFAULT '',
    `cleared_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_target_active` (`target_id`, `active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_fines` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `target_id` INT NOT NULL,
    `target_name` VARCHAR(64) NOT NULL DEFAULT '',
    `officer_id` INT NOT NULL,
    `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
    `category` VARCHAR(32) NOT NULL,
    `category_label` VARCHAR(64) NOT NULL DEFAULT '',
    `fine_id` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NOT NULL,
    `amount` INT NOT NULL,
    `status` VARCHAR(16) NOT NULL DEFAULT 'unpaid',
    `created_at` INT NOT NULL,
    `paid_at` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `idx_target_status` (`target_id`, `status`),
    KEY `idx_officer` (`officer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_jail` (
    `user_id` INT NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `officer_id` INT NOT NULL DEFAULT 0,
    `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
    `reason_id` VARCHAR(64) NOT NULL DEFAULT '',
    `reason_label` VARCHAR(128) NOT NULL DEFAULT '',
    `total_seconds` INT NOT NULL,
    `remaining_seconds` INT NOT NULL,
    `added_seconds` INT NOT NULL DEFAULT 0,
    `reduced_seconds` INT NOT NULL DEFAULT 0,
    `started_at` INT NOT NULL,
    `updated_at` INT NOT NULL,
    `clothing` MEDIUMTEXT NULL,
    `was_cuffed` TINYINT NOT NULL DEFAULT 0,
    PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_jail_history` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `user_id` INT NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `officer_id` INT NOT NULL DEFAULT 0,
    `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
    `reason_label` VARCHAR(128) NOT NULL DEFAULT '',
    `total_seconds` INT NOT NULL DEFAULT 0,
    `started_at` INT NOT NULL DEFAULT 0,
    `ended_at` INT NOT NULL DEFAULT 0,
    `end_type` VARCHAR(16) NOT NULL DEFAULT '',
    `released_by_id` INT NOT NULL DEFAULT 0,
    `released_by_name` VARCHAR(64) NOT NULL DEFAULT '',
    `release_reason` VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (`id`),
    KEY `idx_user` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_impounds` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(16) NOT NULL,
    `model` VARCHAR(64) NOT NULL DEFAULT '',
    `owner_id` INT NOT NULL,
    `owner_name` VARCHAR(64) NOT NULL DEFAULT '',
    `officer_id` INT NOT NULL,
    `officer_name` VARCHAR(64) NOT NULL DEFAULT '',
    `location_id` VARCHAR(32) NOT NULL,
    `reason` VARCHAR(128) NOT NULL,
    `fee` INT NOT NULL DEFAULT 0,
    `status` VARCHAR(16) NOT NULL DEFAULT 'impounded',
    `created_at` INT NOT NULL,
    `released_at` INT NOT NULL DEFAULT 0,
    `release_type` VARCHAR(16) NOT NULL DEFAULT '',
    `released_by_id` INT NOT NULL DEFAULT 0,
    `released_by_name` VARCHAR(64) NOT NULL DEFAULT '',
    PRIMARY KEY (`id`),
    KEY `idx_plate_status` (`plate`, `status`),
    KEY `idx_owner_status` (`owner_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `evora_police_logs` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `category` VARCHAR(32) NOT NULL,
    `action` VARCHAR(64) NOT NULL,
    `actor_id` INT NOT NULL DEFAULT 0,
    `actor_name` VARCHAR(64) NOT NULL DEFAULT '',
    `target_id` INT NOT NULL DEFAULT 0,
    `target_name` VARCHAR(64) NOT NULL DEFAULT '',
    `details` TEXT NULL,
    `created_at` INT NOT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_category` (`category`),
    KEY `idx_actor` (`actor_id`),
    KEY `idx_target` (`target_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
