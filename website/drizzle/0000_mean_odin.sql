CREATE TABLE `jessy_access_audit` (
	`id` text PRIMARY KEY NOT NULL,
	`request_id` text NOT NULL,
	`actor` text NOT NULL,
	`action` text NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jessy_access_requests` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`email` text NOT NULL,
	`status` text DEFAULT 'pending' NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`decided_by` text,
	`notification_status` text DEFAULT 'not_sent' NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `jessy_access_requests_user_id_unique` ON `jessy_access_requests` (`user_id`);--> statement-breakpoint
CREATE TABLE `jessy_mail_settings` (
	`id` text PRIMARY KEY NOT NULL,
	`value` text NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `jessy_oauth_states` (
	`state_hash` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`expires_at` integer NOT NULL
);
