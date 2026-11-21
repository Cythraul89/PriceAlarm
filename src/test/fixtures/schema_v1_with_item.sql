-- Schema version 1 database written by commit 359451e (before lastAlarmAt),
-- with one item and one offer. Used by the v1 -> v2 migration test.
CREATE TABLE "items" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "target_price" TEXT NOT NULL, "currency" TEXT NOT NULL DEFAULT 'CHF', "check_time" INTEGER NOT NULL DEFAULT 480, "enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)), "alarm_active" INTEGER NOT NULL DEFAULT 0 CHECK ("alarm_active" IN (0, 1)), "last_run_at" INTEGER NULL, "created_at" INTEGER NOT NULL, PRIMARY KEY ("id"));
INSERT INTO "items" VALUES('50ee4b13-faeb-426d-bae9-07bf6c49be91','radon','3000','CHF',1055,1,0,NULL,1795276800);
CREATE TABLE "offers" ("id" TEXT NOT NULL, "item_id" TEXT NOT NULL REFERENCES items (id) ON DELETE CASCADE, "url" TEXT NOT NULL, "shop_name" TEXT NOT NULL, "fetch_mode" TEXT NOT NULL DEFAULT 'auto', "resolved_method" TEXT NULL, "last_price" TEXT NULL, "last_currency" TEXT NULL, "last_availability" TEXT NULL, "last_status" TEXT NULL, "last_error" TEXT NULL, "last_checked_at" INTEGER NULL, PRIMARY KEY ("id"), UNIQUE ("item_id", "url"));
INSERT INTO "offers" VALUES('8812737b-4bc9-498c-97c2-891a5f21a313','50ee4b13-faeb-426d-bae9-07bf6c49be91','https://www.brack.ch/x','Brack','auto',NULL,NULL,NULL,NULL,NULL,NULL,NULL);
CREATE TABLE "price_checks" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "offer_id" TEXT NOT NULL REFERENCES offers (id) ON DELETE CASCADE, "checked_at" INTEGER NOT NULL, "status" TEXT NOT NULL, "method" TEXT NULL, "price" TEXT NULL, "currency" TEXT NULL, "availability" TEXT NULL, "error" TEXT NULL);
CREATE TABLE "settings" ("id" INTEGER NOT NULL DEFAULT 1, "theme_mode" TEXT NOT NULL DEFAULT 'system', PRIMARY KEY ("id"));
INSERT INTO "settings" VALUES(1,'system');
CREATE INDEX price_checks_offer_time ON price_checks (offer_id, checked_at);
DELETE FROM "sqlite_sequence";
PRAGMA user_version = 1;
