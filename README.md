# ISALAB Odoo 16 Custom Modules

Custom addons and configuration for Odoo 16 (migrated from Odoo 15).

## 📁 Structure

```
isalab16-custom/
├── custom_addons/           # Custom modules (migrated)
├── custom_3rdP_addons/      # Third-party modules
│   ├── module_from_oca/
│   └── module_from_other_vendor/
├── isa16.cfg.template       # Configuration template
└── README.md
```

## 🚀 Setup

```bash
# Clone into /opt/odoo/
cd /opt/odoo
git clone https://github.com/A-zeril-A/isalab16-custom.git isalab16-custom

# Run setup script (from isalab15-custom)
cd /opt/odoo/isalab15-custom/scripts
sudo ./setup_odoo_version.sh 16
```

## 🔄 Migration from v15

Use the migration backup from Odoo 15:
```
/opt/odoo/backups/isalab15_for_v16_*/
```

## 🚀 Start Odoo 16

```bash
sudo -u odoo -H /opt/odoo/isalab16/venv_isalab16/bin/python3 \
  /opt/odoo/isalab16/odoo-bin -c /opt/odoo/isalab16/config/isa16.cfg
```

Web: http://SERVER_IP:8016

