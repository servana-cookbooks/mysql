

node['mysql']['server']['packages'].each do |package_name|
  package package_name do
    action :remove
  end
end

package "libaio-dev" do 
	action :install
end

case node['kernel']['machine']
when "x86_64"
    get_mysql =  "mysql-5.6.12-debian6.0-x86_64.deb"
when "i686"
    get_mysql =  "mysql-5.6.12-debian6.0-i686.deb"
else
    get_mysql =  "mysql-5.6.12-debian6.0-i686.deb"
end

execute  "wget -O /tmp/#{get_mysql} http://dev.mysql.com/get/Downloads/MySQL-5.6/#{get_mysql}/from/http://cdn.mysql.com/"

directory "/var/log/mysql" do
	action :create
	owner "mysql"
	group "mysql"
end

execute "chown -R mysql:mysql /var/run/mysqld"

#group "mysql" do
#  system true
#  action :create
#end

#user "mysql" do
#  gid "mysql"
#  shell "/bin/bash"
#  supports :manage_home => false
#  system true
#  action :create
#end

node.set['mysql']['basedir'] = "/opt/mysql/server-5.6" 

dpkg_package "mysql-server" do
  source "/tmp/#{get_mysql}"
  action :install
end

execute "/etc/profile.d/mysql.sh" do
command <<-COMMAND
(
cat <<'EOF'
#!/bin/bash 
export PATH=#{node['mysql']['basedir']}/bin:$PATH
EOF
) > /etc/profile.d/mysql.sh
COMMAND
action :run
end

link "/etc/init.d/mysql" do
	to "/opt/mysql/server-5.6/support-files/mysql.server"
end

link "/etc/my.cnf" do
	to "/etc/mysql/my.cnf"
end


#execute "#{node['mysql']['basedir']}/bin/mysqlcheck -uroot -p#{node['mysql']['server_root_password']} --all-databases=true"
#execute "#{node['mysql']['basedir']}/bin/mysql_upgrade -uroot -p#{node['mysql']['server_root_password']} --all-databases=true"
 
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


