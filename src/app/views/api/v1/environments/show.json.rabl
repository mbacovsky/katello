object false

glue(@environment) do
  attributes :id, :created_at, :name, :description, :prior_id, :label, :updated_at, :organization_id, :library
  node(:prior) { |e| e.prior.name }
  node(:organization) { |e| e.organization.name }
  node(:api) { |e| @_env['action_dispatch.request.parameters']['controller'] }
  node(:path) { |e| @_env['PATH_INFO'] }
end

