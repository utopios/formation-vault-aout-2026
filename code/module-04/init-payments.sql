-- TP 4 (PayLink) — table des paiements.
-- Le numero de carte n'est JAMAIS stocke en clair : la colonne
-- card_number_encrypted recoit le ciphertext transit (format vault:vN:...).
-- Chargement : podman exec -i postgres psql -U postgres -d paylink < init-payments.sql

CREATE TABLE IF NOT EXISTS payments (
    id                    SERIAL      PRIMARY KEY,
    reference             TEXT        NOT NULL UNIQUE,
    amount_cents          INTEGER     NOT NULL CHECK (amount_cents > 0),
    currency              CHAR(3)     NOT NULL DEFAULT 'EUR',
    card_number_encrypted TEXT        NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
