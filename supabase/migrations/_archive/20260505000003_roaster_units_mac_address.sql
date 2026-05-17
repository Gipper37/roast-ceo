-- ============================================================================
-- Persist a roaster controller's MAC address as the durable identifier.
--
-- Background: a roaster's IP is allocated by the local network's DHCP
-- and changes whenever the network reboots, the lease expires, or the
-- shop's router gets replaced. The controller's MAC address is burned
-- in at the factory and never changes. That's the right key for
-- "this is the same physical Loring as before."
--
-- Stored on roaster_units so STRATA can:
--   • Re-discover a roaster after IP change without prompting
--   • Distinguish two Lorings on the same network
--   • Auto-link scan results to existing roaster units (silent UX)
--
-- NULL is allowed for legacy + manually-added units that haven't yet
-- been scan-discovered. Populated lazily on first successful scan.
-- ============================================================================

BEGIN;

ALTER TABLE roaster_units
  ADD COLUMN IF NOT EXISTS mac_address text;

COMMENT ON COLUMN roaster_units.mac_address IS
  'Controller MAC address (lowercased, colon-delimited) read from the '
  'OS ARP cache during a network scan. Durable across DHCP changes — '
  'matched to identify "this is the same physical roaster" on re-scans. '
  'NULL until a scan-discovery event populates it.';

-- A single MAC can only map to one roaster unit per company at a time.
-- Helpful both for the auto-link logic AND to prevent two facilities
-- in one company from claiming the same controller.
CREATE UNIQUE INDEX IF NOT EXISTS idx_roaster_units_mac_unique_per_company
  ON roaster_units (company_id, mac_address)
  WHERE mac_address IS NOT NULL;

COMMIT;
