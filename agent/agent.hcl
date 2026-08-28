# Vault Agent — demo 5.1 (standalone, conteneur podman sur le reseau vault-lab)
# Lancement : vault agent -config=/agent/agent.hcl

pid_file = "/agent/pidfile"

vault {
  # Nom DNS du conteneur "vault" sur le reseau podman vault-lab
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path                   = "/agent/role_id"
      secret_id_file_path                 = "/agent/secret_id"
      # true par defaut : l'agent supprime le fichier secret_id apres lecture
      # (livraison a usage unique). false en lab pour pouvoir redemarrer l'agent.
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/agent/out/vault-token"
    }
  }
}

template_config {
  # Les secrets KV statiques n'ont pas de lease : l'agent les re-lit
  # periodiquement. Defaut : 5m. 10s ici pour rendre la rotation visible
  # pendant la demo (en production, gardez un intervalle raisonnable).
  static_secret_render_interval = "10s"
}

template {
  source      = "/agent/app.env.ctmpl"
  destination = "/agent/out/app.env"
}
