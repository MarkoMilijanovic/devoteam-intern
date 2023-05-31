provider "google" {
  project = var.project
}

provider "google-beta" {
  project = var.project
}

resource "google_compute_network" "default" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_firewall" "http-firewall" {
  depends_on = [ google_compute_network.default ]
  name = "tr-allow-http"
  network = var.network_name
  allow {
    protocol = "tcp"
    ports = ["80"]
  }
  source_tags = [ "http-server" ]
}

resource "google_compute_firewall" "firewall-rule-front-back" {
  depends_on = [ google_compute_network.default ]
  name = "tr-firewall-rule-front-back"
  network = var.network_name
  allow {
    protocol = "tcp"
    ports = ["3000-3001"]
  }
  source_ranges = [ "0.0.0.0/0" ]
}

resource "google_compute_firewall" "firewall-rule-ssh" {
  depends_on = [ google_compute_network.default ]
  name = "tr-firewall-rule-ssh"
  network = var.network_name
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
  source_ranges = [ "0.0.0.0/0" ]
}

resource "google_compute_subnetwork" "default" {
  name                     = "tr-subnet"
  ip_cidr_range            = "10.127.0.0/20"
  network                  = google_compute_network.default.self_link
  region                   = var.region
  private_ip_google_access = true
}

resource "google_compute_instance_template" "default" {
    name = "tr-instancetemplate"
    machine_type         = "n1-standard-1"
    disk{
        source_image = "projects/cloud-internship-marko/global/images/intern-image-new"
    }
    network_interface {
      network = var.network_name
      subnetwork = google_compute_subnetwork.default.id
      access_config {}   
    }
    tags = [ "http-server" ]
    metadata_startup_script = <<SCRIPT
#! /bin/bash
cd /home/marko_milijanovic2001/cloud_student_internship/
cat > frontend/.env.development <<EOF
REACT_APP_API_URL=http://$(curl ifconfig.me.):3001/api
EOF
docker-compose build
docker-compose up -d
SCRIPT
}

module "mig" {
  source            = "terraform-google-modules/vm/google//modules/mig"
  version           = "~> 7.9"
  instance_template = google_compute_instance_template.default.self_link
  region            = var.region
  hostname          = var.network_name
  target_size       = 2
  named_ports = [{
    name = "http",
    port = 3000
  },
  {
    name = "http",
    port = 3001
  }
  ]
  network    = var.network_name
  subnetwork = "tr-subnet"
}

module "gce-lb-http" {
  source            = "GoogleCloudPlatform/lb-http/google"
  name              = "tr-loadbalancer"
  project           = var.project
  target_tags       = [var.network_name]
  firewall_networks = [var.network_name]

  backends = {
    default = {
      description                     = null
      protocol                        = "HTTP"
      port                            = 80
      port_name                       = "http"
      timeout_sec                     = 10
      connection_draining_timeout_sec = null
      enable_cdn                      = false
      compression_mode                = null
      edge_security_policy            = null
      security_policy                 = null
      session_affinity                = null
      affinity_cookie_ttl_sec         = null
      custom_request_headers          = null
      custom_response_headers         = null

      health_check = {
        check_interval_sec  = 10
        timeout_sec         = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
        request_path        = "/"
        port                = 3000
        host = null
        logging = null
      }

      log_config = {
        enable      = false
        sample_rate = null
      }

      groups = [
        {
          group                        = module.mig.instance_group
          balancing_mode               = null
          capacity_scaler              = null
          description                  = null
          max_connections              = null
          max_rate_per_instance        = null
          max_rate_per_endpoint        = null
          max_utilization              = null
          max_connections_per_instance = null
          max_connections_per_endpoint = null
          max_rate                     = null
        }
      ]

      iap_config = {
        enable               = false
        oauth2_client_id     = ""
        oauth2_client_secret = ""
      }
    }
  }
}