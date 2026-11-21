CREATE TABLE `jessy_usage_events` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`email` text NOT NULL,
	`event` text NOT NULL,
	`created_at` integer NOT NULL
);
