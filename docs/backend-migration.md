# Backend Migration

The root backend moves from `states/homelab-kubernetes/au` to `homelab` in the
existing `homelab-opentofu` GCS bucket. This is a state-address change, not an
infrastructure recreation.

Do not initialise the changed backend until this migration is separately
approved. Freeze applies, securely pull a state backup and address inventory
from the old prefix, then run the exact reviewed `tofu init -migrate-state`
operation from a trusted workstation. Compare the before and after address
inventories and require a saved no-op plan before any resource change.

Keep the old versioned state objects access-controlled until the new prefix has
completed a successful plan and the rollback window has passed. Rollback means
restoring the previous `backend.tf`, reinitialising against the old prefix, and
confirming its address inventory; it never means recreating resources.
