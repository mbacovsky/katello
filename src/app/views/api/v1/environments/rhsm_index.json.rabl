collection @all_environments, :object_root => false

%w(id name description).map do |attr|
  node attr do |e|
    e[attr.to_sym]
  end
end
