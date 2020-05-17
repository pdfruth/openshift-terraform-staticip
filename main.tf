locals {
  bootstrap_fqdns     = ["bootstrap.${var.cluster_domain}"]
  lb_fqdns            = ["loadbalancer.${var.cluster_domain}"]
  api_lb_fqdns        = formatlist("%s.%s", ["api", "api-int", "*.apps"], var.cluster_domain)
  control_plane_fqdns = [for idx in range(var.control_plane_count) : "master${idx + 1}.${var.cluster_domain}"]
  compute_fqdns       = [for idx in range(var.compute_count) : "worker${idx + 1}.${var.cluster_domain}"]
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "compute_cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vm_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vm_template
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_folder" "folder" {
  path          = var.cluster_name
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

module "lb" {
  source        = "./lb"
  lb_ip_address = var.lb_ip_address

  api_backend_addresses = flatten([
    [var.bootstrap_ip_address],
    var.control_plane_ip_addresses
  ])

  ingress_backend_addresses = var.compute_ip_addresses
  ssh_public_key_path       = var.ssh_public_key_path
}

module "lb_vm" {
  source = "./vm"

  ignition               = module.lb.ignition
  ignition_file_url      = null

  hostnames_ip_addresses = zipmap(
    local.lb_fqdns,
    [var.lb_ip_address]
  )

  resource_pool_id      = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id          = data.vsphere_datastore.datastore.id
  datacenter_id         = data.vsphere_datacenter.dc.id
  network_id            = data.vsphere_network.network.id
  folder_id             = vsphere_folder.folder.path
  guest_id              = data.vsphere_virtual_machine.template.guest_id
  template_uuid         = data.vsphere_virtual_machine.template.id
  disk_thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned

  cluster_name   = var.cluster_name
  cluster_domain = var.cluster_domain
  machine_cidr   = var.machine_cidr

  num_cpus      = 2
  memory        = 2048
  dns_addresses = var.vm_dns_addresses
}

module "bootstrap_vm" {
  source = "./vm"

  ignition              = null
  ignition_file_url     = "${var.ignition_url}/bootstrap.ign"

  hostnames_ip_addresses = zipmap(
    local.bootstrap_fqdns,
    [var.bootstrap_ip_address]
  )

  resource_pool_id      = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id          = data.vsphere_datastore.datastore.id
  datacenter_id         = data.vsphere_datacenter.dc.id
  network_id            = data.vsphere_network.network.id
  folder_id             = vsphere_folder.folder.path
  guest_id              = data.vsphere_virtual_machine.template.guest_id
  template_uuid         = data.vsphere_virtual_machine.template.id
  disk_thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned

  cluster_name   = var.cluster_name
  cluster_domain = var.cluster_domain
  machine_cidr   = var.machine_cidr

  num_cpus      = 4
  memory        = 8192
  dns_addresses = var.vm_dns_addresses
}

module "control_plane_vm" {
  source = "./vm"

  ignition              = null
  ignition_file_url     = "${var.ignition_url}/master.ign"

  hostnames_ip_addresses = zipmap(
    local.control_plane_fqdns,
    var.control_plane_ip_addresses
  )

  resource_pool_id      = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id          = data.vsphere_datastore.datastore.id
  datacenter_id         = data.vsphere_datacenter.dc.id
  network_id            = data.vsphere_network.network.id
  folder_id             = vsphere_folder.folder.path
  guest_id              = data.vsphere_virtual_machine.template.guest_id
  template_uuid         = data.vsphere_virtual_machine.template.id
  disk_thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned

  cluster_name   = var.cluster_name
  cluster_domain = var.cluster_domain
  machine_cidr   = var.machine_cidr

  num_cpus      = var.control_plane_num_cpus
  memory        = var.control_plane_memory
  dns_addresses = var.vm_dns_addresses
}

module "compute_vm" {
  source = "./vm"

  ignition              = null
  ignition_file_url     = "${var.ignition_url}/worker.ign"

  hostnames_ip_addresses = zipmap(
    local.compute_fqdns,
    var.compute_ip_addresses
  )

  resource_pool_id      = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id          = data.vsphere_datastore.datastore.id
  datacenter_id         = data.vsphere_datacenter.dc.id
  network_id            = data.vsphere_network.network.id
  folder_id             = vsphere_folder.folder.path
  guest_id              = data.vsphere_virtual_machine.template.guest_id
  template_uuid         = data.vsphere_virtual_machine.template.id
  disk_thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned

  cluster_name   = var.cluster_name
  cluster_domain = var.cluster_domain
  machine_cidr   = var.machine_cidr

  num_cpus      = var.compute_num_cpus
  memory        = var.compute_memory
  dns_addresses = var.vm_dns_addresses
}

