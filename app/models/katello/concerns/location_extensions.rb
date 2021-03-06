#
# Copyright 2014 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

module Katello
  module Concerns
    module LocationExtensions
      extend ActiveSupport::Concern

      included do
        after_initialize :set_default_overrides, :if => :new_record?
      end

      def set_default_overrides
        self.ignore_types << ::ConfigTemplate.name
        self.ignore_types << ::Hostgroup.name
      end

      module ClassMethods
        def default_location
          # In the future, we should have a better way to identify the 'default' location
          Location.where(:katello_default => true).first
        end
      end
    end
  end
end
