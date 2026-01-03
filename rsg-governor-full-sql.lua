-- --------------------------------------------------------

--
-- Table structure for table `governor_boss_salaries`
--

CREATE TABLE `governor_boss_salaries` (
  `job_name` varchar(64) NOT NULL,
  `salary` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_boss_salaries`
--
ALTER TABLE `governor_boss_salaries`
  ADD PRIMARY KEY (`job_name`);
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_business_permits`
--

CREATE TABLE `governor_business_permits` (
  `id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `char_name` varchar(100) NOT NULL,
  `business_name` varchar(100) NOT NULL,
  `license_type` varchar(32) NOT NULL DEFAULT 'general',
  `status` enum('pending','approved','rejected','autoapproved') NOT NULL DEFAULT 'pending',
  `auto_after_secs` int(11) NOT NULL DEFAULT 600,
  `submitted_at` int(10) UNSIGNED NOT NULL,
  `decided_at` int(10) UNSIGNED DEFAULT NULL,
  `decided_by` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_business_permits`
--
ALTER TABLE `governor_business_permits`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_govperm_region_status` (`region_name`,`status`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_business_permits`
--
ALTER TABLE `governor_business_permits`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_deputies`
--

CREATE TABLE `governor_deputies` (
  `id` int(11) NOT NULL,
  `region_hash` varchar(16) NOT NULL,
  `citizenid` varchar(64) NOT NULL,
  `char_name` varchar(128) NOT NULL,
  `role` varchar(32) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_deputies`
--
ALTER TABLE `governor_deputies`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_region_citizen` (`region_hash`,`citizenid`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_deputies`
--
ALTER TABLE `governor_deputies`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_duty_sessions`
--

CREATE TABLE `governor_duty_sessions` (
  `id` int(10) UNSIGNED NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `job_name` varchar(64) NOT NULL,
  `job_label` varchar(128) DEFAULT NULL,
  `job_type` varchar(32) DEFAULT NULL,
  `grade` int(11) NOT NULL DEFAULT 0,
  `region_name` varchar(64) NOT NULL,
  `started_at` datetime NOT NULL,
  `ended_at` datetime DEFAULT NULL,
  `minutes_regular` int(11) NOT NULL DEFAULT 0,
  `minutes_overtime` int(11) NOT NULL DEFAULT 0,
  `paid` tinyint(1) NOT NULL DEFAULT 0,
  `ig_start_year` int(11) DEFAULT NULL,
  `ig_start_month` int(11) DEFAULT NULL,
  `ig_start_day` int(11) DEFAULT NULL,
  `ig_start_hour` int(11) DEFAULT NULL,
  `ig_start_minute` int(11) DEFAULT NULL,
  `ig_end_year` int(11) DEFAULT NULL,
  `ig_end_month` int(11) DEFAULT NULL,
  `ig_end_day` int(11) DEFAULT NULL,
  `ig_end_hour` int(11) DEFAULT NULL,
  `ig_end_minute` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for table `governor_duty_sessions`
--
ALTER TABLE `governor_duty_sessions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_citizen_paid` (`citizenid`,`paid`),
  ADD KEY `idx_region_paid` (`region_name`,`paid`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_duty_sessions`
--
ALTER TABLE `governor_duty_sessions`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_laws`
--

CREATE TABLE `governor_laws` (
  `id` int(11) NOT NULL,
  `region_hash` varchar(16) NOT NULL,
  `title` varchar(100) NOT NULL,
  `body` text NOT NULL,
  `created_by` varchar(64) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_laws`
--
ALTER TABLE `governor_laws`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_laws`
--
ALTER TABLE `governor_laws`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_office_heads`
--

CREATE TABLE `governor_office_heads` (
  `id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `office_key` varchar(64) NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `char_name` varchar(100) NOT NULL,
  `assigned_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `governor_office_heads`
--
ALTER TABLE `governor_office_heads`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_gohead_region_office` (`region_name`,`office_key`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_office_heads`
--
ALTER TABLE `governor_office_heads`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_office_settings`
--

CREATE TABLE `governor_office_settings` (
  `region_alias` varchar(50) NOT NULL,
  `job_name` varchar(50) NOT NULL,
  `pay_mode` varchar(16) NOT NULL DEFAULT 'manual',
  `auto_schedule` varchar(32) DEFAULT 'weekly',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_office_settings`
--
ALTER TABLE `governor_office_settings`
  ADD PRIMARY KEY (`region_alias`,`job_name`);
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_offices`
--

CREATE TABLE `governor_offices` (
  `id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `office_key` varchar(64) NOT NULL,
  `office_label` varchar(100) NOT NULL,
  `base_salary_cents` int(11) NOT NULL DEFAULT 0,
  `salary_share` float NOT NULL DEFAULT 0,
  `supply_share` float NOT NULL DEFAULT 0,
  `funding_share` decimal(5,4) NOT NULL DEFAULT 0.0000,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_offices`
--
ALTER TABLE `governor_offices`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_goffice_region_key` (`region_name`,`office_key`),
  ADD UNIQUE KEY `uniq_gov_office_region_key` (`region_name`,`office_key`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_offices`
--
ALTER TABLE `governor_offices`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=44;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_pay_prefs`
--

CREATE TABLE `governor_pay_prefs` (
  `citizenid` varchar(50) NOT NULL,
  `pay_mode` varchar(16) NOT NULL DEFAULT 'cash',
  `bank_branch` varchar(32) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_pay_prefs`
--
ALTER TABLE `governor_pay_prefs`
  ADD PRIMARY KEY (`citizenid`);
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_permits`
--

CREATE TABLE `governor_permits` (
  `id` int(11) NOT NULL,
  `region_hash` varchar(16) NOT NULL,
  `citizenid` varchar(64) NOT NULL,
  `char_name` varchar(128) NOT NULL,
  `permit_type` varchar(32) NOT NULL,
  `expires_at` datetime DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `governor_permits`
--
ALTER TABLE `governor_permits`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_permits`
--
ALTER TABLE `governor_permits`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_region_announcements`
--

CREATE TABLE `governor_region_announcements` (
  `id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `message` text NOT NULL,
  `author` varchar(50) DEFAULT NULL,
  `created_at` int(10) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `governor_region_announcements`
--
ALTER TABLE `governor_region_announcements`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_govann_region_time` (`region_name`,`created_at`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_region_announcements`
--
ALTER TABLE `governor_region_announcements`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_region_rules`
--

CREATE TABLE `governor_region_rules` (
  `id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `rules_text` text NOT NULL,
  `updated_by` varchar(50) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `governor_region_rules`
--
ALTER TABLE `governor_region_rules`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_govrules_region` (`region_name`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_region_rules`
--
ALTER TABLE `governor_region_rules`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governor_terms`
--

CREATE TABLE `governor_terms` (
  `id` int(10) UNSIGNED NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `region_alias` varchar(64) NOT NULL,
  `job_name` varchar(64) NOT NULL,
  `previous_job` varchar(64) DEFAULT NULL,
  `previous_grade` int(11) DEFAULT NULL,
  `term_start` datetime NOT NULL DEFAULT current_timestamp(),
  `term_end` datetime DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `governor_terms`
--
ALTER TABLE `governor_terms`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_citizenid` (`citizenid`),
  ADD KEY `idx_region_alias` (`region_alias`),
  ADD KEY `idx_active` (`active`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governor_terms`
--
ALTER TABLE `governor_terms`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `governors`
--

CREATE TABLE `governors` (
  `id` int(10) UNSIGNED NOT NULL,
  `identifier` varchar(64) NOT NULL,
  `citizenid` varchar(50) DEFAULT NULL,
  `region_hash` varchar(16) NOT NULL,
  `region_alias` varchar(64) DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `character_name` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `removed_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `governors`
--
ALTER TABLE `governors`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uniq_region` (`region_hash`),
  ADD KEY `idx_identifier` (`identifier`),
  ADD KEY `idx_gov_identifier` (`identifier`),
  ADD KEY `idx_gov_alias` (`region_alias`),
  ADD KEY `idx_gov_hash_active` (`region_hash`,`active`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `governors`
--
ALTER TABLE `governors`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;
