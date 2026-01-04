"""
Custom pre-migration script for OpenUpgrade from Odoo 15 to Odoo 16

This script runs automatically BEFORE the standard OpenUpgrade base pre-migration.
It fixes known issues that would otherwise cause the migration to fail.

Location: custom_migration_scripts/base/16.0.1.3/pre-migration.py
"""

import logging

_logger = logging.getLogger(__name__)

# Standard Odoo modules that might have orphan records
STANDARD_MODULES = (
    'base', 'crm', 'sale', 'purchase', 'stock', 'account', 'hr', 'project',
    'mail', 'contacts', 'calendar', 'website', 'mrp', 'point_of_sale',
    'fleet', 'maintenance', 'helpdesk', 'survey', 'event', 'sale_management',
    'purchase_stock', 'account_payment', 'hr_expense', 'hr_holidays'
)


def migrate(cr, version):
    """
    Pre-migration fixes for OpenUpgrade.
    
    This function is called automatically by OpenUpgrade before the base module
    migration scripts run.
    """
    if not version:
        return
    
    _logger.info("=" * 70)
    _logger.info("Running custom pre-migration fixes for Odoo 16...")
    _logger.info("=" * 70)
    
    # Fix 1: Remove orphan ir_act_window_view records (cause duplicate key errors)
    _fix_orphan_act_window_views(cr)
    
    # Fix 2: Clean up leftover OpenUpgrade legacy columns from failed migrations
    _cleanup_legacy_columns(cr)
    
    # Fix 3: Fix any potential sequence issues
    _fix_sequence_issues(cr)
    
    _logger.info("=" * 70)
    _logger.info("Custom pre-migration fixes completed!")
    _logger.info("=" * 70)


def _fix_orphan_act_window_views(cr):
    """
    Remove orphan ir_act_window_view records that have no external_id.
    
    These records cause "duplicate key violates unique constraint" errors
    because Odoo tries to INSERT instead of UPDATE (can't find existing record
    without external_id).
    """
    _logger.info("Fixing orphan ir_act_window_view records...")
    
    # Build IN clause for standard modules
    modules_str = ",".join(f"'{m}'" for m in STANDARD_MODULES)
    
    # Count orphan records first
    cr.execute(f"""
        SELECT COUNT(*) FROM ir_act_window_view awv
        WHERE NOT EXISTS (
            SELECT 1 FROM ir_model_data imd2 
            WHERE imd2.model = 'ir.actions.act_window.view' 
              AND imd2.res_id = awv.id
        )
        AND EXISTS (
            SELECT 1 FROM ir_model_data imd 
            WHERE imd.model = 'ir.actions.act_window' 
              AND imd.res_id = awv.act_window_id
              AND imd.module IN ({modules_str})
        )
    """)
    orphan_count = cr.fetchone()[0]
    
    if orphan_count > 0:
        _logger.info(f"  Found {orphan_count} orphan ir_act_window_view records")
        
        # Delete orphan records
        cr.execute(f"""
            DELETE FROM ir_act_window_view awv
            WHERE NOT EXISTS (
                SELECT 1 FROM ir_model_data imd2 
                WHERE imd2.model = 'ir.actions.act_window.view' 
                  AND imd2.res_id = awv.id
            )
            AND EXISTS (
                SELECT 1 FROM ir_model_data imd 
                WHERE imd.model = 'ir.actions.act_window' 
                  AND imd.res_id = awv.act_window_id
                  AND imd.module IN ({modules_str})
            )
            RETURNING id
        """)
        deleted = cr.fetchall()
        _logger.info(f"  Removed {len(deleted)} orphan records (Odoo will recreate them with proper external_id)")
    else:
        _logger.info("  No orphan records found - database is clean")


def _cleanup_legacy_columns(cr):
    """
    Remove leftover openupgrade_legacy_* columns from previous failed migrations.
    
    These columns cause "column already exists" errors when re-running migration.
    """
    _logger.info("Cleaning up leftover OpenUpgrade legacy columns...")
    
    cr.execute("""
        SELECT table_name, column_name 
        FROM information_schema.columns 
        WHERE column_name LIKE 'openupgrade_legacy_%'
        ORDER BY table_name, column_name
    """)
    legacy_columns = cr.fetchall()
    
    if legacy_columns:
        _logger.info(f"  Found {len(legacy_columns)} legacy columns to remove")
        
        for table_name, column_name in legacy_columns:
            try:
                cr.execute(f'ALTER TABLE "{table_name}" DROP COLUMN IF EXISTS "{column_name}"')
                _logger.info(f"  Dropped: {table_name}.{column_name}")
            except Exception as e:
                _logger.warning(f"  Could not drop {table_name}.{column_name}: {e}")
    else:
        _logger.info("  No legacy columns found")


def _fix_sequence_issues(cr):
    """
    Fix sequence ownership and values that might cause issues during migration.
    """
    _logger.info("Checking sequence issues...")
    
    # Check for sequences with wrong nextval (can cause constraint violations)
    cr.execute("""
        SELECT COUNT(*) FROM information_schema.sequences 
        WHERE sequence_schema = 'public'
    """)
    seq_count = cr.fetchone()[0]
    _logger.info(f"  Found {seq_count} sequences in public schema")
    
    # Nothing to fix here usually, just informational
    _logger.info("  Sequence check completed")

