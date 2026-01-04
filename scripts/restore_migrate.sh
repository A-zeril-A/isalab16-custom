#!/bin/bash
# =============================================================================
# Restore & Run OpenUpgrade Migration Script for Odoo 16
# =============================================================================
# This script:
# 1. Drops existing isalab database (from previous migration)
# 2. Creates new database from template or backup
# 3. Runs OpenUpgrade migration command with live log
# 4. Creates backup for next version migration (isalab16_for_v17_xxx)
# =============================================================================

set -e

# Configuration
VERSION="16"
NEXT_VERSION="17"
BACKUP_DIR="/opt/odoo/backups"
BACKUP_PATTERN="isalab15_for_v${VERSION}_"
TEMPLATE_DB="isalab15_for_v${VERSION}_T"
TARGET_DB="isalab"
PG_USER="odoo"

# Odoo paths
ODOO_DIR="/opt/odoo/isalab${VERSION}"
VENV_DIR="${ODOO_DIR}/venv_isalab${VERSION}"
MIGRATE_CFG="${ODOO_DIR}/config/myodoo${VERSION}_migrate.cfg"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  🔄 Odoo ${VERSION} - OpenUpgrade Migration Tool${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_info() {
    echo -e "  ${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "  ${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "  ${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "  ${RED}❌ $1${NC}"
}

print_step() {
    echo ""
    echo -e "  ${MAGENTA}▶ STEP $1: $2${NC}"
    echo ""
}

# Check if database exists
db_exists() {
    sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$1"
}

# Drop database if exists
drop_db() {
    local db_name="$1"
    if db_exists "$db_name"; then
        print_warning "Dropping existing database: $db_name"
        sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$db_name';" > /dev/null 2>&1 || true
        sudo -u postgres dropdb "$db_name"
        print_success "Database dropped: $db_name"
    else
        print_info "Database does not exist: $db_name"
    fi
}

# List available backups
list_backups() {
    echo ""
    echo -e "  ${CYAN}📦 Available Migration Backups:${NC}"
    echo ""
    
    local i=1
    BACKUP_LIST=()
    
    for dir in "$BACKUP_DIR"/${BACKUP_PATTERN}*/; do
        if [ -d "$dir" ]; then
            local backup_name=$(basename "$dir")
            local backup_file=$(find "$dir" -name "*.backup" -o -name "*.dump" 2>/dev/null | head -1)
            
            if [ -n "$backup_file" ]; then
                local size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
                local date_part=$(echo "$backup_name" | grep -oP '\d{8}_\d{6}' | head -1)
                
                if [ -n "$date_part" ]; then
                    local formatted_date="${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${date_part:9:2}:${date_part:11:2}"
                else
                    formatted_date="Unknown"
                fi
                
                BACKUP_LIST+=("$backup_file")
                printf "    ${GREEN}[%d]${NC} %s ${YELLOW}(%s)${NC} - %s\n" "$i" "$backup_name" "$size" "$formatted_date"
                ((i++))
            fi
        fi
    done
    
    if [ ${#BACKUP_LIST[@]} -eq 0 ]; then
        print_error "No backups found matching pattern: ${BACKUP_PATTERN}*"
        return 1
    fi
    
    echo ""
    return 0
}

# Restore backup to template database
restore_to_template() {
    local backup_file="$1"
    
    print_info "Restoring backup to template database..."
    echo -e "    Backup: ${YELLOW}$(basename "$backup_file")${NC}"
    echo -e "    Target: ${YELLOW}${TEMPLATE_DB}${NC}"
    echo ""
    
    # Drop existing template if exists
    drop_db "$TEMPLATE_DB"
    
    # Create empty database
    print_info "Creating template database..."
    sudo -u postgres createdb -O "$PG_USER" "$TEMPLATE_DB"
    
    # Restore
    print_info "Restoring backup (this may take a while)..."
    sudo -u postgres pg_restore -d "$TEMPLATE_DB" --no-owner --no-privileges "$backup_file" 2>&1 || true
    
    print_success "Template database created: $TEMPLATE_DB"
}

# Create target database from template
create_from_template() {
    print_info "Creating database from template..."
    echo -e "    Template: ${YELLOW}${TEMPLATE_DB}${NC}"
    echo -e "    Target:   ${YELLOW}${TARGET_DB}${NC}"
    echo ""
    
    # Drop existing target if exists
    drop_db "$TARGET_DB"
    
    # Disconnect all sessions from template
    sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$TEMPLATE_DB';" > /dev/null 2>&1 || true
    
    # Create from template
    sudo -u postgres createdb -T "$TEMPLATE_DB" -O "$PG_USER" "$TARGET_DB"
    
    print_success "Database created: $TARGET_DB (from template)"
}

# Run OpenUpgrade migration
run_migration() {
    print_step "3" "Running OpenUpgrade Migration"
    
    echo -e "    ${CYAN}Odoo Dir:${NC}    ${YELLOW}${ODOO_DIR}${NC}"
    echo -e "    ${CYAN}Config:${NC}      ${YELLOW}${MIGRATE_CFG}${NC}"
    echo -e "    ${CYAN}Database:${NC}    ${YELLOW}${TARGET_DB}${NC}"
    echo ""
    
    if [ ! -f "$MIGRATE_CFG" ]; then
        print_error "Migration config not found: $MIGRATE_CFG"
        exit 1
    fi
    
    if [ ! -d "$VENV_DIR" ]; then
        print_error "Virtual environment not found: $VENV_DIR"
        exit 1
    fi
    
    print_info "Starting migration (live log)..."
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Run migration with live output
    sudo -u odoo bash -c "cd ${ODOO_DIR} && source ${VENV_DIR}/bin/activate && python odoo-bin -c ${MIGRATE_CFG} -d ${TARGET_DB} --update=all --stop-after-init"
    
    local exit_code=$?
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ $exit_code -eq 0 ]; then
        print_success "Migration completed successfully!"
        return 0
    else
        print_error "Migration failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Create backup for next version
create_backup_for_next() {
    print_step "4" "Create Backup for v${NEXT_VERSION} Migration"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="isalab${VERSION}_for_v${NEXT_VERSION}_${timestamp}"
    local backup_folder="${BACKUP_DIR}/${backup_name}"
    local backup_file="${backup_folder}/${backup_name}.backup"
    
    echo -e "    ${CYAN}Source DB:${NC}    ${YELLOW}${TARGET_DB}${NC}"
    echo -e "    ${CYAN}Backup:${NC}       ${YELLOW}${backup_name}${NC}"
    echo ""
    
    # Create backup directory
    mkdir -p "$backup_folder"
    
    # Create README
    cat > "${backup_folder}/README.txt" << EOF
Backup Information
==================
Source Database: ${TARGET_DB}
Source Version:  Odoo ${VERSION}
Target Version:  Odoo ${NEXT_VERSION}
Created:         $(date '+%Y-%m-%d %H:%M:%S')
Server:          $(hostname)

This backup is ready for migration to Odoo ${NEXT_VERSION}
EOF
    
    print_info "Creating backup (this may take a while)..."
    
    # Create backup
    sudo -u postgres pg_dump -Fc -f "$backup_file" "$TARGET_DB"
    
    local size=$(du -h "$backup_file" | cut -f1)
    
    print_success "Backup created: ${backup_name} (${size})"
    echo ""
    echo -e "    ${CYAN}Location:${NC} ${YELLOW}${backup_folder}${NC}"
    echo ""
    print_info "Ready for next migration: v${VERSION} → v${NEXT_VERSION}"
}

# Main menu
main() {
    print_header
    
    # Check prerequisites
    if [ ! -d "$ODOO_DIR" ]; then
        print_error "Odoo directory not found: $ODOO_DIR"
        print_info "Run setup_odoo_version.sh ${VERSION} first"
        exit 1
    fi
    
    print_step "1" "Database Preparation"
    
    # Check if template exists
    if db_exists "$TEMPLATE_DB"; then
        echo -e "  ${GREEN}📋 Template database exists:${NC} ${YELLOW}${TEMPLATE_DB}${NC}"
        echo ""
        echo -e "  ${CYAN}What would you like to do?${NC}"
        echo ""
        echo -e "    ${GREEN}[1]${NC} Create ${YELLOW}${TARGET_DB}${NC} from existing template (fast)"
        echo -e "    ${GREEN}[2]${NC} Restore new backup to template (replace)"
        echo -e "    ${GREEN}[3]${NC} Exit"
        echo ""
        read -p "  Select option [1-3]: " choice
        
        case $choice in
            1)
                print_step "2" "Creating Database from Template"
                create_from_template
                ;;
            2)
                if ! list_backups; then
                    exit 1
                fi
                read -p "  Select backup number: " backup_num
                
                if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ] && [ "$backup_num" -le ${#BACKUP_LIST[@]} ]; then
                    selected_backup="${BACKUP_LIST[$((backup_num-1))]}"
                    print_step "2" "Restoring Backup to Template"
                    restore_to_template "$selected_backup"
                    create_from_template
                else
                    print_error "Invalid selection"
                    exit 1
                fi
                ;;
            3)
                echo ""
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                exit 1
                ;;
        esac
    else
        echo -e "  ${YELLOW}📋 No template database found:${NC} ${TEMPLATE_DB}"
        echo ""
        
        if ! list_backups; then
            exit 1
        fi
        read -p "  Select backup number to restore: " backup_num
        
        if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ] && [ "$backup_num" -le ${#BACKUP_LIST[@]} ]; then
            selected_backup="${BACKUP_LIST[$((backup_num-1))]}"
            print_step "2" "Restoring Backup to Template"
            restore_to_template "$selected_backup"
            create_from_template
        else
            print_error "Invalid selection"
            exit 1
        fi
    fi
    
    # Ask to run migration
    echo ""
    read -p "  Run OpenUpgrade migration now? [Y/n]: " run_choice
    
    if [[ ! "$run_choice" =~ ^[Nn]$ ]]; then
        if run_migration; then
            # Migration successful - ask about backup
            echo ""
            echo -e "  ${GREEN}🎉 Migration to v${VERSION} completed!${NC}"
            echo ""
            echo -e "  ${CYAN}Before creating backup for v${NEXT_VERSION}, please verify:${NC}"
            echo -e "    - Test the migrated database in Odoo"
            echo -e "    - Check for any errors or issues"
            echo ""
            read -p "  Migration verified OK? Create backup for v${NEXT_VERSION}? [y/N]: " backup_choice
            
            if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
                create_backup_for_next
            else
                print_info "Skipping backup. You can run it later manually."
            fi
        fi
    else
        print_info "Skipping migration. You can run it manually:"
        echo ""
        echo -e "    ${YELLOW}sudo -u odoo bash -c \"cd ${ODOO_DIR} && source ${VENV_DIR}/bin/activate && python odoo-bin -c ${MIGRATE_CFG} -d ${TARGET_DB} --update=all --stop-after-init\"${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✨ Done!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Run
main
