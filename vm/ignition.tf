locals {
  ignition_encoded = var.ignition != null ? "data:text/plain;charset=utf-8;base64,${base64encode(var.ignition)}" : var.ignition_file_url
}

data "ignition_file" "hostname" {
  for_each = var.hostnames_ip_addresses

  filesystem = "root"
  path       = "/etc/hostname"
  mode       = "420"

  content {
    content = element(split(".", each.key), 0)
  }
}

data "ignition_file" "static_ip" {
  for_each = var.hostnames_ip_addresses

  filesystem = "root"
  path       = "/etc/sysconfig/network-scripts/ifcfg-ens192"
  mode       = "420"

  content {
    content = templatefile("${path.module}/ifcfg.tmpl", {
      dns_addresses = var.dns_addresses,
      machine_cidr  = var.machine_cidr
      ip_address     = each.value
      base_domain = var.base_domain
    })
  }
}

data "ignition_systemd_unit" "restart" {
  for_each = var.hostnames_ip_addresses

  name = "restart.service"

  content = <<EOF
[Unit]
ConditionFirstBoot=yes
[Service]
Type=idle
ExecStart=/sbin/reboot
[Install]
WantedBy=multi-user.target
EOF
}

data "ignition_config" "ign" {
  for_each = var.hostnames_ip_addresses

  append {
    source = local.ignition_encoded
  }

  systemd = [
    "${data.ignition_systemd_unit.restart[each.key].rendered}",
  ]

  files = [
    data.ignition_file.hostname[each.key].rendered,
    data.ignition_file.static_ip[each.key].rendered,
  ]
}
