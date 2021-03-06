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

require 'katello_test_helper'
require 'support/pulp/task_support'

module Katello
class GluePulpRepoTestBase < ActiveSupport::TestCase
  include TaskSupport

  def self.before_suite
    super

    services  = ['Candlepin', 'ElasticSearch', 'Foreman']
    models    = ['KTEnvironment', 'Repository', 'Package', 'ContentView',
                 'Organization', 'Product', 'ContentViewEnvironment']
    disable_glue_layers(services, models, true)

    configure_runcible

    @@fedora_17_x86_64 = Repository.find(@loaded_fixtures['katello_repositories']['fedora_17_x86_64']['id'])
    @@fedora_17_x86_64.relative_path = '/test_path/'
    @@fedora_17_x86_64.feed = "file:///var/www/test_repos/zoo"
  end

  def self.delete_repo(repo)
    ::ForemanTasks.sync_task(::Actions::Pulp::Repository::Destroy, :pulp_id => repo.pulp_id)
  end

  def delete_repo(repo)
    GluePulpRepoTestBase.delete_repo(repo)
  end

  def create_repo(repo)
    GluePulpRepoTestBase.create_repo(repo)
  end

  def self.create_repo(repository)
    ::ForemanTasks.sync_task(::Actions::Pulp::Repository::Create,
                            content_type: repository.content_type,
                            pulp_id: repository.pulp_id,
                            name: repository.name,
                            feed: repository.feed,
                            ssl_ca_cert: repository.feed_ca,
                            ssl_client_cert: repository.feed_cert,
                            ssl_client_key: repository.feed_key,
                            unprotected: repository.unprotected,
                            checksum_type: repository.checksum_type,
                            path: repository.relative_path,
                            with_importer: true)
  end

end

class GluePulpRepoTestCreateDestroy < GluePulpRepoTestBase

  def setup
    super
    @fedora_17_x86_64 = @@fedora_17_x86_64
    VCR.insert_cassette('pulp/repository/create')
  end

  def teardown
    VCR.eject_cassette
  end

  def test_create_pulp_repo
    assert create_repo(@fedora_17_x86_64)
    delete_repo(@fedora_17_x86_64)
  end

end

class GluePulpRepoTest < GluePulpRepoTestBase

  def self.before_suite
    super
    VCR.insert_cassette('pulp/repository/repository')
    self.create_repo(@@fedora_17_x86_64)
  end

  def self.after_suite
    delete_repo(@@fedora_17_x86_64)
    VCR.eject_cassette
  end

  def setup
    super
    @fedora_17_x86_64 = @@fedora_17_x86_64
    @fedora_17_x86_64.relative_path = '/test_path/'
  end

  def test_delete_orphaned_content
    assert Repository.delete_orphaned_content.is_a?(Hash)
  end

  def test_relative_path
    assert_equal '/test_path/', @fedora_17_x86_64.relative_path
  end

  def test_relative_path=
    @fedora_17_x86_64.relative_path = '/new_path/'

    refute_equal '/test_path/', @fedora_17_x86_64.relative_path
  end

  def test_generate_distributors
    dists = @fedora_17_x86_64.generate_distributors
    refute_empty dists.select{|d| d.is_a? Runcible::Models::YumDistributor}
    refute_empty dists.select{|d| d.is_a? Runcible::Models::YumCloneDistributor}
  end

  def test_update_unprotected
    @fedora_17_x86_64.expects(:refresh_pulp_repo).once.returns(true)
    @fedora_17_x86_64.expects(:generate_metadata).once.returns(true)
    @fedora_17_x86_64.unprotected = !@fedora_17_x86_64.unprotected
    @fedora_17_x86_64.save!
  end

  def test_populate_from
    assert @fedora_17_x86_64.populate_from({ @fedora_17_x86_64.pulp_id => {} })
  end

  def test_sync
    task_list = @fedora_17_x86_64.sync
    refute_empty    task_list
    assert_kind_of  PulpSyncStatus, task_list.first
    TaskSupport.wait_on_tasks(task_list)
  end

  def test_set_sync_schedule
    time = "2013-08-01T00:00:00-04:00/P1D"
    assert @fedora_17_x86_64.set_sync_schedule(time)
  end

end


class GluePulpRepoAfterSyncTest < GluePulpRepoTestBase

  def self.before_suite
    super
    VCR.insert_cassette('pulp/repository/after_sync')
    create_repo(@@fedora_17_x86_64)
  end

  def self.after_suite
    delete_repo(@@fedora_17_x86_64)
    VCR.eject_cassette
  end

  def setup
    super
    @fedora_17_x86_64 = @@fedora_17_x86_64
    @fedora_17_x86_64.relative_path = '/test_path/'
  end

  def test_handle_sync_complete_task
    mock_notifier = Minitest::Mock.new
    mock_notifier.expect(:success, nil)

    task_list = @fedora_17_x86_64.sync
    TaskSupport.wait_on_tasks(task_list)

    @fedora_17_x86_64.handle_sync_complete_task(task_list.first.uuid, mock_notifier)

    assert PulpTaskStatus.where(:uuid => task_list.first.uuid).length > 0
  end

end


class GluePulpChangeFeedTest < GluePulpRepoTestBase

  def self.before_suite
    super
    VCR.insert_cassette('pulp/repository/feed_change')
    create_repo(@@fedora_17_x86_64)
  end

  def self.after_suite
    delete_repo(@@fedora_17_x86_64)
    VCR.eject_cassette
  end

  def test_feed_change
    new_feed = "http://foo.com/foo"
    @@fedora_17_x86_64.feed = new_feed
    @@fedora_17_x86_64.save!
    pulps_feed = Repository.find(@@fedora_17_x86_64.id).pulp_repo_facts['importers'].first['config']['feed']
    assert_equal new_feed, pulps_feed
  end
end

class GluePulpPuppetRepoTest < GluePulpRepoTestBase

  @@p_forge = nil

  def self.before_suite
    super
    VCR.insert_cassette('pulp/repository/puppet')
    @@p_forge = Repository.find(@loaded_fixtures['katello_repositories']['p_forge']['id'])
    @@p_forge.relative_path = '/test_path/'
    @@p_forge.feed = "http://davidd.fedorapeople.org/repos/random_puppet/"
    create_repo(@@p_forge)
  end

  def self.after_suite
    delete_repo(@@p_forge)
    VCR.eject_cassette
  end

  def setup
    super
    @p_forge = @@p_forge
    @p_forge.relative_path = '/test_path/'
  end

  def test_generate_distributors
    refute_nil @@p_forge.find_distributor
  end

  def test_upload_puppet_module
    Repository.any_instance.expects(:trigger_contents_changed).with() do |options|
      options[:wait] == false && options[:reindex] == false
    end

    @filepath = File.join(Katello::Engine.root, "test/fixtures/puppet/puppetlabs-ntp-2.0.1.tar.gz")
    @p_forge.upload_content([@filepath])

    assert_includes @p_forge.puppet_modules.map(&:name), "ntp"
  end
end


class GluePulpRepoContentsTest < GluePulpRepoTestBase

  def self.before_suite
    super
    VCR.insert_cassette('pulp/repository/contents')

    @@fedora_17_x86_64.create_pulp_repo
    task_list = @@fedora_17_x86_64.sync
    TaskSupport.wait_on_tasks(task_list)
  end

  def self.after_suite
    delete_repo(@@fedora_17_x86_64)
    VCR.eject_cassette
  end

  def test_last_sync
    assert @@fedora_17_x86_64.last_sync
  end

  def test_generate_metadata
    refute_empty @@fedora_17_x86_64.generate_metadata
  end

  def test_sync_status
    assert_kind_of PulpSyncStatus, @@fedora_17_x86_64.sync_status
  end

  def test_sync_state
    assert_equal PulpSyncStatus::FINISHED, @@fedora_17_x86_64.sync_state
  end

  def test_successful_sync?
    assert @@fedora_17_x86_64.successful_sync?(@@fedora_17_x86_64.sync_status)
  end

  def test_synced?
    assert @@fedora_17_x86_64.synced?
  end

  def test_sync_finish
    refute_nil @@fedora_17_x86_64.sync_finish
  end

  def test_sync_start
    refute_nil @@fedora_17_x86_64.sync_start
  end

  def test_packages
    refute_empty @@fedora_17_x86_64.packages.select { |package| package.name == 'elephant' }
  end

  def test_has_package?
    pkg_id = @@fedora_17_x86_64.packages.sort_by(&:id).first.id
    assert @@fedora_17_x86_64.has_package?(pkg_id)
  end

  def test_errata
    refute_empty @@fedora_17_x86_64.errata.select { |errata| errata.errata_id == "RHEA-2010:0002" }
  end

  def test_has_erratum?
    e_id = @@fedora_17_x86_64.errata.first.errata_id
    assert @@fedora_17_x86_64.has_erratum?(e_id)
  end

  def test_distributions
    distributions = @@fedora_17_x86_64.distributions

    refute_empty distributions.select { |distribution| distribution.id == "ks-Test Family-TestVariant-16-x86_64" }
  end

  def test_has_distribution?
    assert @@fedora_17_x86_64.has_distribution?("ks-Test Family-TestVariant-16-x86_64")
  end

  def test_find_packages_by_name
    refute_empty @@fedora_17_x86_64.find_packages_by_name('elephant')
  end

  def test_find_packages_by_nvre
    refute_empty @@fedora_17_x86_64.find_packages_by_nvre('elephant', '0.3', '0.8', '0')
  end

  def test_find_latest_packages_by_name
    refute_empty @@fedora_17_x86_64.find_latest_packages_by_name('elephant')
  end

  def test_package_groups
    package_groups = @@fedora_17_x86_64.package_groups

    refute_empty package_groups.select { |group| group.name == 'mammal' }
  end

  def test_package_group_categories
    categories = @@fedora_17_x86_64.package_group_categories

    refute_empty categories.select { |category| category['name'] == 'all' }
  end

  def test_trigger_contents_changed_index_units
    Katello.config.stubs(:use_elasticsearch).returns(:true)
    pkg = @@fedora_17_x86_64.find_packages_by_nvre('elephant', '0.3', '0.8', '0')[0]
    @@fedora_17_x86_64.expects(:generate_metadata).returns([])
    Package.expects(:index_packages).with([pkg['_id']])

    unit = {:checksumtype => pkg['checksumtype'], :checksum => pkg['checksum'] }
    @@fedora_17_x86_64.trigger_contents_changed(:publish => true, :reindex => false, :index_units => [{:unit => unit}])
  end

end


class GluePulpRepoOperationsTest < GluePulpRepoTestBase

  def self.before_suite
    super
    VCR.insert_cassette('pulp/repository/operations')

    @@fedora_17_x86_64_dev = Repository.find(@loaded_fixtures['katello_repositories']['fedora_17_x86_64_dev']['id'])

    @@fedora_17_x86_64.create_pulp_repo
    task_list = @@fedora_17_x86_64.sync
    TaskSupport.wait_on_tasks(task_list)
  end

  def self.after_suite
    delete_repo(@@fedora_17_x86_64)
    VCR.eject_cassette
  end

  def test_create_clone
    staging = KTEnvironment.find(katello_environments(:staging).id)
    clone = @@fedora_17_x86_64.create_clone(:environment => staging)

    assert_kind_of Repository, clone
  ensure
    clone.destroy
    assert_empty Repository.where(:id=>clone.id)
  end

  def test_clone_contents
    dev = KTEnvironment.find(katello_environments(:dev).id)
    @@fedora_17_x86_64_dev.relative_path = Repository.clone_repo_path(:repository => @@fedora_17_x86_64,
                                                                      :environment => dev,
                                                                      :content_view => dev.default_content_view)
    @@fedora_17_x86_64_dev.create_pulp_repo

    task_list = @@fedora_17_x86_64.clone_contents(@@fedora_17_x86_64_dev)
    assert_equal 5, task_list.length

    TaskSupport.wait_on_tasks(task_list)
  ensure
    delete_repo(@@fedora_17_x86_64_dev)
  end

end
end
