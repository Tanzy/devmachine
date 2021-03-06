# -*- mode: ruby -*-
# vi: set ft=ruby :

dir = Dir.pwd
vagrant_dir = File.expand_path(File.dirname(__FILE__))

Vagrant.configure("2") do |config|

  # Store the current version of Vagrant for use in conditionals when dealing
  # with possible backward compatible issues.
  vagrant_version = Vagrant::VERSION.sub /^v/, ""


  # Default Ubuntu Box
  #
  # This box is provided by Ubuntu vagrantcloud.com and is a nicely sized (332MB)
  # box containing the Ubuntu 14.04 Trusty 64 bit release. Once this box is downloaded
  # to your host computer, it is cached for future use under the specified box name.
  config.vm.box = "boxcutter/ubuntu1404"

  # Configurations from 1.0.x can be placed in Vagrant 1.1.x specs like the following.
  # Configuration options for the VMware Fusion provider.
  config.vm.provider :vmware_fusion do |v, override|
    override.vm.box_version = "2.0.13"
    v.vmx["memsize"] = "1024"
    v.vmx["numvcpus"] = "1"
  end

  config.vm.provider "parallels" do |prl, override|
    prl.name = "basebox"
    prl.update_guest_tools = true
    override.vm.box = "parallels/ubuntu-14.04"
    prl.memory = 1024
    prl.cpus = 2
  end

  # SSH Agent Forwarding
  #
  # Enable agent forwarding on vagrant ssh commands. This allows you to use ssh keys
  # on your host machine inside the guest. See the manual for `ssh-add`.
  config.ssh.forward_agent = true


  config.vm.hostname = "basebox"
  
  if Vagrant.has_plugin?("vagrant-cachier")
    # Configure cached packages to be shared between instances of the same base box.
    # More info on http://fgrehm.viewdocs.io/vagrant-cachier/usage
    config.cache.scope = :box
    
  end
  
  # Local Machine Hosts
  #
  # If the Vagrant plugin hostsupdater (https://github.com/cogitatio/vagrant-hostsupdater) is
  # installed, the following will automatically configure your local machine's hosts file to
  # be aware of the domains specified below. Watch the provisioning script as you may need to
  # enter a password for Vagrant to access your hosts file.
  #
  # By default, we'll include the domains set up by basebox through the basebox-hosts file
  # located in the www/ directory.
  #
  # Other domains can be automatically added by including a basebox-hosts file containing
  # individual domains separated by whitespace in subdirectories of www/.
  if defined? VagrantPlugins::HostsUpdater
    # Recursively fetch the paths to all basebox-hosts files under the www/ directory.
    paths = Dir[File.join(vagrant_dir, "www", "**", "basebox-hosts")]

    # Parse the found basebox-hosts files for host names.
    hosts = paths.map do |path|
      # Read line from file and remove line breaks
      lines = File.readlines(path).map(&:chomp)
      # Filter out comments starting with "#"
      lines.grep(/\A[^#]/)
    end.flatten.uniq # Remove duplicate entries

    # Pass the found host names to the hostsupdater plugin so it can perform magic.
    config.hostsupdater.aliases = hosts
    config.hostsupdater.remove_on_suspend = true
  end

  # Private Network (default)
  #
  # A private network is created by default. This is the IP address through which your
  # host machine will communicate to the guest. In this default configuration, the virtual
  # machine will have an IP address of 192.168.57.4 and a virtual network adapter will be
  # created on your host machine with the IP of 192.168.57.1 as a gateway.
  #
  # Access to the guest machine is only available to your local host. To provide access to
  # other devices, a public network should be configured or port forwarding enabled.
  #
  # Note: If your existing network is using the 192.168.50.x subnet, this default IP address
  # should be changed. If more than one VM is running, including other
  # Vagrant machines, different subnets should be used for each.
  #
  config.vm.network :private_network, :id => "basebox_primary", :ip => "10.37.132.4"

  # Drive mapping
  #
  # The following config.vm.synced_folder settings will map directories in your Vagrant
  # virtual machine to directories on your local machine. Once these are mapped, any
  # changes made to the files in these directories will affect both the local and virtual
  # machine versions. Think of it as two different ways to access the same file. When the
  # virtual machine is destroyed with `vagrant destroy`, your files will remain in your local
  # environment.

  # /srv/database/
  #
  # If a database directory exists in the same directory as your Vagrantfile,
  # a mapped directory inside the VM will be created that contains these files.
  # This directory is used to maintain default database scripts as well as backed
  # up mysql dumps (SQL files) that are to be imported automatically on vagrant up
  config.vm.synced_folder "database/", "/srv/database"

  # If the mysql_upgrade_info file from a previous persistent database mapping is detected,
  # we'll continue to map that directory as /var/lib/mysql inside the virtual machine. Once
  # this file is changed or removed, this mapping will no longer occur. A db_backup command
  # is now available inside the virtual machine to backup all databases for future use. This
  # command is automatically issued on halt, suspend, and destroy if the vagrant-triggers
  # plugin is installed.
  if File.exist?(File.join(vagrant_dir,'database/data/mysql_upgrade_info')) then
    config.vm.synced_folder "database/data/", "/var/lib/mysql", :mount_options => []
  end

  # /srv/config/
  #
  # If a server-conf directory exists in the same directory as your Vagrantfile,
  # a mapped directory inside the VM will be created that contains these files.
  # This directory is currently used to maintain various config files for php and
  # Apache as well as any pre-existing database files.
  config.vm.synced_folder "config/", "/srv/config"

  # /srv/log/
  #
  # If a log directory exists in the same directory as your Vagrantfile, a mapped
  # directory inside the VM will be created for some generated log files.
  config.vm.synced_folder "log/", "/srv/log", :owner => "vagrant", :group => "www-data"
  config.vm.synced_folder "log/apache2", "/var/log/apache2", :owner => "vagrant", :group => "www-data"
  #config.vm.synced_folder "log/nginx", "/var/log/apache2/", :owner => "vagrant", :group => "www-data"


  # /srv/www/
  #
  # If a www directory exists in the same directory as your Vagrantfile, a mapped directory
  # inside the VM will be created that acts as the default location for Apache sites. Put all
  # of your project files here that you want to access through the web server
  config.vm.synced_folder "www/", "/srv/www/"

  # Fix 'no tty' output
  config.vm.provision "fix-no-tty", type: "shell" do |s|
    s.privileged = false
    s.inline = "sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
  end

  # Customfile - POSSIBLY UNSTABLE
  #
  # Use this to insert your own (and possibly rewrite) Vagrant config lines. Helpful
  # for mapping additional drives. If a file 'Customfile' exists in the same directory
  # as this Vagrantfile, it will be evaluated as ruby inline as it loads.
  #
  # Note that if you find yourself using a Customfile for anything crazy or specifying
  # different provisioning, then you may want to consider a new Vagrantfile entirely.
  if File.exist? File.join(vagrant_dir, "Customfile")
    eval IO.read(File.join(vagrant_dir, "Customfile")), binding
  end

  # Provisioning
  #
  # Process one or more provisioning scripts depending on the existence of custom files.
  #
  # provison-pre.sh acts as a pre-hook to our default provisioning script. Anything that
  # should run before the shell commands laid out in provision.sh (or your provision-custom.sh
  # file) should go in this script. If it does not exist, no extra provisioning will run.
  if File.exist?(File.join(vagrant_dir,'provision','provision-pre.sh')) then
    config.vm.provision :shell, :path => File.join( "provision", "provision-pre.sh" )
  end

  # provision.sh or provision-custom.sh
  #
  # By default, Vagrantfile is set to use the provision.sh bash script located in the
  # provision directory. If it is detected that a provision-custom.sh script has been
  # created, that is run as a replacement. This is an opportunity to replace the entirety
  # of the provisioning provided by default.
  if File.exist?(File.join(vagrant_dir,'provision','provision-custom.sh')) then
    config.vm.provision :shell, :path => File.join("provision", "provision-custom.sh")
  else
    config.vm.provision :shell, :path => File.join("provision", "provision.sh")
  end

  
  # provision-post.sh acts as a post-hook to the default provisioning. Anything that should
  # run after the shell commands laid out in provision.sh or provision-custom.sh should be
  # put into this file. This provides a good opportunity to install additional packages
  # without having to replace the entire default provisioning script.
  if File.exist?(File.join(vagrant_dir,'provision','provision-post.sh')) then
    config.vm.provision :shell, :path => File.join( "provision", "provision-post.sh" ), run: "always"
  end

  # Always start MySQL on boot, even when not running the full provisioner
  # (run: "always" support added in 1.6.0)
  if vagrant_version >= "1.6.0"
    if File.exist?(File.join(vagrant_dir,'provision','restartServices.sh')) then
      config.vm.provision :shell, :path => File.join( "provision", "restartServices.sh" ), run: "always"
    else
      config.vm.provision :shell, :inline => "sudo service mysql restart", :run => "always"
      config.vm.provision :shell, :inline => "sudo service apache2 restart", :run => "always"
      config.vm.provision :shell, :inline => "sudo service elasticsearch restart", :run => "always"
      config.vm.provision :shell, :inline => "sudo service kibana4 restart", :run => "always"
      config.vm.provision :shell, :inline => "sudo service rabbitmq-server restart", :run => "always"
    end
  end

  # Vagrant Triggers
  #
  # If the vagrant-triggers plugin is installed, we can run various scripts on Vagrant
  # state changes like `vagrant up`, `vagrant halt`, `vagrant suspend`, and `vagrant destroy`
  #
  # These scripts are run on the host machine, so we use `vagrant ssh` to tunnel back
  # into the VM and execute things. By default, each of these scripts calls db_backup
  # to create backups of all current databases. This can be overridden with custom
  # scripting. See the individual files in config/homebin/ for details.
  if defined? VagrantPlugins::Triggers
    config.trigger.after :up, :stdout => true do
      #run "vagrant ssh -c 'vagrant_up'"
    end
    config.trigger.before :reload, :stdout => true do
      #run "vagrant ssh -c 'vagrant_halt'"
    end
    config.trigger.after :reload, :stdout => true do
      #run "vagrant ssh -c 'vagrant_up'"
    end
    config.trigger.before :halt, :stdout => true do
      #run "vagrant ssh -c 'vagrant_halt'"
    end
    config.trigger.before :suspend, :stdout => true do
      #run "vagrant ssh -c 'vagrant_suspend'"
    end
    config.trigger.before :destroy, :stdout => true do
      run "vagrant ssh -c 'vagrant_destroy'"
    end
  end
end