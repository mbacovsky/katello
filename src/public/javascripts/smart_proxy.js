        /**
 Copyright 2011 Red Hat, Inc.

 This software is licensed to you under the GNU General Public
 License as published by the Free Software Foundation; either version
 2 of the License (GPLv2) or (at your option) any later version.
 There is NO WARRANTY for this software, express or implied,
 including the implied warranties of MERCHANTABILITY,
 NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
 have received a copy of GPLv2 along with this software; if not, see
 http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.
 */

KT.panel.list.registerPage('smart_proxies', {create: 'new_smart_proxy'});



KT.smart_proxy_page = (function() {
    var updateSmartProxy = function() {
        var button = $(this),
            url = button.attr("data-url"),
            smart_proxy_data = {};

        if (button.hasClass("disabled"))
            return;

        $.ajax({
            type: "PUT",
            url: url,
            data: { "smart_proxy": smart_proxies_data },
            cache: false
        });
    },
    register = function() {
        $('#update_smart_proxy').live('click', updateSmartProxy);
    };

    return {
        register: register
    }
}());


$(document).ready(function() {

    KT.panel.set_expand_cb(function(){
        KT.smart_proxy_page.register();
    });


});

