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
#
module Katello
class AsyncOperation

  def initialize(status_id, login, object, method_name, args)
    fail NoMethodError, "undefined method `#{method_name}' for #{object.inspect}" unless object.respond_to?(method_name, true)

    @status_id    = status_id
    @login        = login
    @object       = object
    @args         = args
    @method_name  = method_name.to_sym
  end

  def self.current_task_id
    Thread.current['current_delayed_job_task']
  end

  def display_name
    "#{@object.class}##{@method_name}"
  end

  def perform
    User.current = User.find_by_login(@login)

    #Set task id so a job can reference it, currently no better way to do this :/
    Thread.current['current_delayed_job_task'] = @status_id

    # Set the locale for this action
    if User.current && User.current.default_locale
      I18n.locale = User.current.default_locale
    else
      # if user did not set his locale we are not able to detect browser setting here and we have to
      # fall back to system language
      I18n.locale = KTLocale.pick_available_locale Katello.config.system_lang
    end
    Rails.logger.debug "Setting locale: #{I18n.locale}"

    # If the object provided is a Mailer object, the user wants to send an email; therefore,invoke the method with a
    # deliver; otherwise, invoke the method exactly as provided by the user.  Although this seems a bit odd, this is
    # essentially how the delayed job gem would also send mail, if we were using it directly.

    if @object.class == Class && @object.superclass == ActionMailer::Base
      @result = @object.send(@method_name, *@args).deliver.to_s
    elsif @object
      @result = @object.send(@method_name, *@args)
    end
  ensure
    Thread.current['current_delayed_job_task'] = nil
  end

  # limit to one failure
  def max_attempts
    1
  end

  #callbacks
  def before
    s = TaskStatus.find(@status_id)
    s.update_attributes!(:state => TaskStatus::Status::RUNNING, :start_time => current_time)
  end

  def error(job, exception)
    s = TaskStatus.find(@status_id)
    s.update_attributes!(
        :state => TaskStatus::Status::ERROR,
        :finish_time => current_time,
        :result => {:errors => [exception.message, exception.backtrace.join("\n")]})
  end

  def success
    s = TaskStatus.find(@status_id)
    s.update_attributes!(
        :state => TaskStatus::Status::FINISHED,
        :finish_time => current_time,
        :result => @result)
  end

  private

  def current_time
    (ActiveRecord::Base.default_timezone == :utc) ? Time.now.utc : Time.zone.now
    rescue NoMethodError
      Time.now
  end
end
end
