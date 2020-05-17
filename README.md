# Overview
The Terraform scripts here automate the creation of an Openshift cluster on vSphere User Provisioned Infrastructure (UPI) using static IP addresses.  There must be a functional DHCP & DNS already present in the environment.  Due to the way RHCOS VM provisioning works on VMware (even when those VMs will be configured with static IP addresses) a DHCP server is necessary so that each VM can momentarily connect to the network and download their ignition configuration.  However, the final disposition of each VM will ultimately result in a VM that is configure with a static IP.  See [here](https://github.com/openshift/installer/blob/master/docs/user/vsphere/install_upi.md) for more details.

# Reference Documentation:
Official Openshift docs
 * [Installing a cluster on vSphere](https://docs.openshift.com/container-platform/4.3/installing/installing_vsphere/installing-vsphere.html)

Blogs
 * [How to install OpenShift on VMware with Terraform and static IP addresses](https://www.openshift.com/blog/how-to-install-openshift-on-vmware-with-terraform-and-static-ip-addresses)
 * [OpenShift 4.2 vSphere Install with Static IPs](https://www.openshift.com/blog/openshift-4-2-vsphere-install-with-static-ips) 
 * [Deploying a User Provisioned Infrastructure environment for OpenShift 4.1 on vSphere](https://www.openshift.com/blog/deploying-a-user-provisioned-infrastructure-environment-for-openshift-4-1-on-vsphere)
 * [OpenShift 4.2 vSphere Install Quickstart](https://www.openshift.com/blog/openshift-4-2-vsphere-install-quickstart)
 * [OpenShift 4.3 installation on VMware vSphere with static IPs](https://labs.consol.de/container/platform/openshift/2020/01/31/ocp43-installation-vmware.html)

Credits

 The following sources were very instrumental in the creation of this asset
 * [gojeaqui's Git repo](https://github.com/gojeaqui/installer/blob/master/upi/vsphere/README.md)
 * [Openshift install Git repo](https://github.com/openshift/installer/tree/release-4.7/upi/vsphere)
 
# Pre-Requisites

* [Terraform version >= 0.12.24](https://www.terraform.io/downloads.html)
* [VMWare command line tool govc](https://github.com/vmware/govmomi)

# Setup Prerequisites
Prior to using these templates, you must have a functional DHCP and DNS setup running.
Once the pre-reqs are in place, the Terraform scripts here will automate the creation of the following VMs;
 - Load Balancer
 - Boostrap
 - Masters
 - Workers

Install the required packages
```
yum install -y bind-utils httpd dhcp unzip git
```

Download the terraform executable and install it
```
curl -O https://releases.hashicorp.com/terraform/0.12.24/terraform_0.12.24_linux_amd64.zip
unzip terraform_0.12.24_linux_amd64.zip
cp terraform /usr/local/bin
```

Validate version (should be: v0.12.24)
```
terraform version
```

Download and install VMware CLI
```
curl -L https://github.com/vmware/govmomi/releases/download/v0.22.1/govc_linux_amd64.gz > govc_0.22.1_linux_amd64.gz
gunzip govc_0.22.2_linux_amd64.gz
mv govc_0.22.2_linux_amd64 /usr/local/bin/govc
chmod +x /usr/local/bin/govc
```
 * [govc usage](https://github.com/vmware/govmomi/blob/master/govc/USAGE.md)
 
Configure the CLI with the vSphere settings
```
export GOVC_URL='vcenter.example.com'
export GOVC_USERNAME='VSPHERE_ADMIN_USER'
export GOVC_PASSWORD='VSPHERE_ADMIN_PASSWORD'
export GOVC_NETWORK='VM Network'
export GOVC_DATASTORE='Datastore'
export GOVC_INSECURE=1 # If the host above uses a self-signed cert
```

Test the govc CLI settings
```
govc ls
govc about
```

If you don't already have a Folder, you can create a folder to store your template in
```
govc folder.create /Datacenter/vm/Production/ocp4
```

Download the OVA and import it into the Template Repository
```
curl -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.3/4.3.8/rhcos-4.3.8-x86_64-vmware.x86_64.ova
```

Verify that the Template options are the ones you want
```
govc import.spec rhcos-4.3.8-x86_64-vmware.x86_64.ova | python -m json.tool > rhcos.json
vi rhcos.json
```

Import the template and mark it as such
```
govc import.ova -name=rhcos-4.3.8 -pool=/Datacenter/host/Cluster/Resources -ds=Datastore -folder=templates -options=rhcos.json ./rhcos-4.3.8-x86_64-vmware.x86_64.ova
govc vm.markastemplate /Datacenter/vm/templates/rhcos-4.3.8
```

# Build the Cluster
Download the OpenShift client
```
curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.3.19/openshift-install-linux-4.3.19.tar.gz
curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.3.19/openshift-client-linux-4.3.19.tar.gz
tar xzvf openshift-install-linux-4.3.19.tar.gz
tar xzvf openshift-client-linux-4.3.19.tar.gz
cp openshift-install /usr/local/bin
cp oc /usr/local/bin
```

Create a folder for the cluster configuration files
```
mkdir ocp4
```

Create an install-config.yaml
```
cat << EOF > ocp4/install-config.yaml
---
apiVersion: v1
baseDomain: example.com
compute:
- hyperthreading: Enabled
  name: worker
  replicas: 0 
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: 3
metadata:
  name: closprod
platform:
  vsphere:
    vcenter: vcentercc.example.com
    username: VSPHERE_DYNAMIC_PROVISIONING_USER
    password: VSPHERE_DYNAMIC_PROVISIONING_PASSWORD
    datacenter: Cluster
    defaultDatastore: Datastore
networking:
  clusterNetworks:
  - cidr: "10.128.0.0/14"
    hostPrefix: 23
  machineCIDR: "192.168.10.0/24"
  serviceCIDR: "172.30.0.0/16"
fips: false 
pullSecret: '{"auths": ...}'
sshKey: 'ssh-rsa AAAA...' 
EOF
```

Generate the Kubernetes manifests for the cluster
```
openshift-install create manifests --dir=ocp4
```

Set the flag mastersSchedulable to false
```
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/g' ocp4/manifests/cluster-scheduler-02-config.yml
```

Create the ignition config files
```
openshift-install create ignition-configs --dir=ocp4
```

Create a folder for the ignition files in your HTTP server root directory:
```
mkdir /var/www/html/ignition
```

Copy the ignition config files to the HTTP server root directory:
```
cp ocp4/*.ign /var/www/html/ignition
```

Check access to the ignition files through HTTP
```
curl -vk http://bastion.example.com/ignition/bootstrap.ign
curl -vk http://bastion.example.com/ignition/master.ign
curl -vk http://bastion.example.com/ignition/worker.ign
```

Clone the OpenShift installer repo
```
git clone https://github.com/pdfruth/openshift-terraform-staticip.git
```

Change into the terraform scripts folder
```
cd openshift-terraform-staticip
```

Fill out a terraform.tfvars file with the vCenter, Networking and CPU / Memory configuration.
There is an example terraform.tfvars file in this directory named terraform.tfvars.example.
Read this file carefully to see how to complete the tfvars 
```
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

Run `terraform init` to initialize terraform, it will download the required plugins and verify the scripts syntax

Run `terraform plan` to see the changes that terraform is going to apply to the vCenter

Create everything all at once.
 Run `terraform apply -auto-approve`.  
 Terraform will create a folder in the vCenter with the name of the cluster and place the VMs inside that folder.  
 This will create the following VMs;
  - loadbalancer
  - bootstrap
  - master1, master2, master3
  - worker1, worker2, worker3

Or, you can create one tier at a time.  
To create the loadbalancer VM, run `terraform apply -target=module.lb_vm -auto-approve`  
To create the bootstrap VM, run `terraform apply -target=module.bootstrap -auto-approve`  
To create the master VMs, run `terraform apply -target=module.control-plane_vm -auto-approve`  
To create the worker VMs, run `terraform apply -target=module.compute_vm -auto-approve`

Run `openshift-install --dir=ocp4 wait-for bootstrap-complete`. 
Wait for the bootstrapping to complete.

Run `openshift-install --dir=ocp4 wait-for install-complete`. 
Wait for the cluster install to finish.

Enjoy your new OpenShift cluster.

If you need to erase the cluster, run `terraform destroy -auto-approve`.
The *terraform destroy* command uses the terraform metadata generated when you run the *terraform init* and *terraform apply* commands, so terraform knows what has been created and safely deletes that (like an undo).
So it is advisable to avoid deleting the terraform.tfstate file and the hidden directory created.
