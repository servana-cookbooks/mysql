
::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
include_recipe "mysql::client"

package "libaio-dev" do 
	action :install
end

execute  "wget -O /tmp/mysql-5.6.12-debian6.0-i686.deb http://dev.mysql.com/get/Downloads/MySQL-5.6/mysql-5.6.12-debian6.0-i686.deb/from/http://cdn.mysql.com/"

dpkg_package "mysql-server" do
  source "/tmp/mysql-5.6.12-debian6.0-i686.deb"
  action :install
end

node.set_unless['mysql']['server_debian_password'] = secure_password
node.set_unless['mysql']['server_root_password']   = secure_password
node.set_unless['mysql']['server_repl_password']   = secure_password

if platform?(%w{debian ubuntu})

  directory "/var/cache/local/preseeding" do
    owner "root"
    group node['mysql']['root_group']
    mode 0755
    recursive true
  end

  execute "preseed mysql-server" do
    command "debconf-set-selections /var/cache/local/preseeding/mysql-server.seed"
    action :nothing
  end

  template "/var/cache/local/preseeding/mysql-server.seed" do
    source "mysql-server.seed.erb"
    owner "root"
    group node['mysql']['root_group']
    mode "0600"
    notifies :run, resources(:execute => "preseed mysql-server"), :immediately
  end

  template "#{node['mysql']['conf_dir']}/debian.cnf" do
    source "debian.cnf.erb"
    owner "root"
    group node['mysql']['root_group']
    mode "0600"
  end

end

execute "dpkg -i /tmp/mysql-5.6.12-debian6.0-i686.deb"



execute "/etc/profile.d/mysql.sh" do
command <<-COMMAND
(
cat <<'EOF'
#!/bin/bash 
export PATH=$PATH:/opt/mysql/server-5.6/bin/
EOF
) > /etc/profile.d/mysql.sh
COMMAND
action :run
end

link "/etc/init.d/mysqld" do
	to "/opt/mysql/server-5.6/support-files/mysql.server"
end

link "/etc/my.cnf" do
	to "/etc/mysql/my.cnf"
end

unless platform?(%w{debian ubuntu})

  execute "assign-root-password" do
    command "\"#{node['mysql']['mysqladmin_bin']}\" -u root password \"#{node['mysql']['server_root_password']}\""
    action :run
    only_if "\"#{node['mysql']['mysql_bin']}\" -u root -e 'show databases;'"
  end

end

 grants_path = node['mysql']['grants_path']

  begin
    t = resources("template[#{grants_path}]")
  rescue
    Chef::Log.info("Could not find previously defined grants.sql resource")
    t = template grants_path do
      source "grants.sql.erb"
      owner "root" unless platform? 'windows'
      group node['mysql']['root_group'] unless platform? 'windows'
      mode "0600"
      action :create
    end
  end

  if platform? 'windows'
    windows_batch "mysql-install-privileges" do
      command "\"#{node['mysql']['mysql_bin']}\" -u root #{node['mysql']['server_root_password'].empty? ? '' : '-p' }\"#{node['mysql']['server_root_password']}\" < \"#{grants_path}\""
      action :nothing
      subscribes :run, resources("template[#{grants_path}]"), :immediately
    end
  else
    execute "mysql-install-privileges" do
      command "\"#{node['mysql']['mysql_bin']}\" -u root #{node['mysql']['server_root_password'].empty? ? '' : '-p' }\"#{node['mysql']['server_root_password']}\" < \"#{grants_path}\""
      action :nothing
      subscribes :run, resources("template[#{grants_path}]"), :immediately
    end
  end


 service "mysql" do
    service_name node['mysql']['service_name']
    if node['mysql']['use_upstart']
      restart_command "restart mysql"
      stop_command "stop mysql"
      start_command "start mysql"
    end
    supports :status => true, :restart => true, :reload => true
    action :nothing
  end
 
 skip_federated = case node['platform']
                   when 'fedora', 'ubuntu', 'amazon'
                     true
                   when 'centos', 'redhat', 'scientific'
                     node['platform_version'].to_f < 6.0
                   else
                     false
                   end

 template "#{node['mysql']['conf_dir']}/my.cnf" do
    source "my56.cnf.erb"
    owner "root" unless platform? 'windows'
    group node['mysql']['root_group'] unless platform? 'windows'
    mode "0644"
    case node['mysql']['reload_action']
    when 'restart'
      notifies :restart, resources(:service => "mysql"), :immediately
    when 'reload'
      notifies :reload, resources(:service => "mysql"), :immediately
    else
      Chef::Log.info "my.cnf updated but mysql.reload_action is #{node['mysql']['reload_action']}. No action taken."
    end
    variables :skip_federated => skip_federated
  end

#mysql_upgrade
