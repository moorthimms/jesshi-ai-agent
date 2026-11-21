import {sqliteTable,text,integer} from 'drizzle-orm/sqlite-core';
export const accessRequests=sqliteTable('jessy_access_requests',{
 id:text('id').primaryKey(),userId:text('user_id').notNull().unique(),email:text('email').notNull(),
 status:text('status').notNull().default('pending'),createdAt:integer('created_at').notNull(),
 updatedAt:integer('updated_at').notNull(),decidedBy:text('decided_by'),notificationStatus:text('notification_status').notNull().default('not_sent')
});
export const accessAudit=sqliteTable('jessy_access_audit',{
 id:text('id').primaryKey(),requestId:text('request_id').notNull(),actor:text('actor').notNull(),
 action:text('action').notNull(),createdAt:integer('created_at').notNull()
});
export const mailSettings=sqliteTable('jessy_mail_settings',{
 id:text('id').primaryKey(),value:text('value').notNull(),updatedAt:integer('updated_at').notNull()
});
export const oauthStates=sqliteTable('jessy_oauth_states',{
 stateHash:text('state_hash').primaryKey(),userId:text('user_id').notNull(),expiresAt:integer('expires_at').notNull()
});
export const usageEvents=sqliteTable('jessy_usage_events',{
 id:text('id').primaryKey(),userId:text('user_id').notNull(),email:text('email').notNull(),
 event:text('event').notNull(),createdAt:integer('created_at').notNull()
});
