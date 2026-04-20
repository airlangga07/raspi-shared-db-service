-- mikaelairlangga-site
CREATE DATABASE IF NOT EXISTS mikael_site CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'mikael_site_user'@'%' IDENTIFIED BY 'REPLACE_ME_MIKAEL_SITE';
GRANT ALL PRIVILEGES ON mikael_site.* TO 'mikael_site_user'@'%';

FLUSH PRIVILEGES;
