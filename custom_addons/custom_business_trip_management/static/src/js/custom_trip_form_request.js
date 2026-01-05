odoo.define('custom_business_trip_management.form_request', function (require) {
    "use strict";

    const ListController = require('web.ListController');
    const ListView = require('web.ListView');
    const viewRegistry = require('web.view_registry');
    const core = require('web.core');
    const Dialog = require('web.Dialog');

    const MyBusinessTripFormsController = ListController.extend({
        renderButtons: function ($node) {
            this._super.apply(this, arguments);
            if (this.$buttons) {
                const self = this;
                const createButton = $(core.qweb.render('MyBusinessTripForms.buttons', {}));
                createButton.appendTo(this.$buttons);
                createButton.on('click', '.o_list_button_create_request', function () {
                    self._showRequestTypeDialog();
                });
            }
        },

        _showRequestTypeDialog: function () {
            const self = this;
            const $content = $(core.qweb.render('BusinessTripRequestTypeDialog', {}));

            const dialog = new Dialog(this, {
                title: "Create New Business Trip Request",
                $content: $content,
                buttons: [{
                    text: "Cancel",
                    close: true
                }]
            });

            $content.on('click', '.btn-with-quotation', function () {
                dialog.close();
                window.location.href = '/business_trip/quotation_list';
            });
            $content.on('click', '.btn-standalone', function () {
                dialog.close();
                window.location.href = '/business_trip/create_standalone';
            });

            dialog.open();
        }
    });

    const MyBusinessTripFormsView = ListView.extend({
        config: _.extend({}, ListView.prototype.config, {
            Controller: MyBusinessTripFormsController,
        }),
    });

    viewRegistry.add('my_business_trip_forms_view', MyBusinessTripFormsView);
}); 