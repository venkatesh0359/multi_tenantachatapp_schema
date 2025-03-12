-- Create the tenant table
CREATE TABLE tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  subdomain TEXT NOT NULL UNIQUE,
  logo_url TEXT,
  primary_color TEXT DEFAULT '#556cd6',
  secondary_color TEXT DEFAULT '#19857b',
  font TEXT DEFAULT 'Roboto',
  status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'trial', 'pending_approval')) DEFAULT 'trial',
  subscription_tier TEXT NOT NULL DEFAULT 'basic',
  max_query_quota INTEGER NOT NULL DEFAULT 1000,
  current_query_count INTEGER NOT NULL DEFAULT 0,
  billing_cycle_start TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_by UUID,
  is_deleted BOOLEAN DEFAULT FALSE,
  -- Hybrid approach: combine created_at with name hashing for better distribution
  tenant_group_id INTEGER NOT NULL GENERATED ALWAYS AS (
    mod(
      (extract(epoch from created_at)::bigint + abs(hashtext(name))), 
      100
    )
  ) STORED
);

-- Create indexes
CREATE INDEX idx_tenants_subdomain ON tenants(subdomain);
CREATE INDEX idx_tenants_tenant_group_id ON tenants(tenant_group_id);
CREATE INDEX idx_tenants_status ON tenants(status);

-- Enable Row Level Security
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;

-- Replace FOR ALL policy with separate policies for each operation type
-- Super users can select tenants
CREATE POLICY super_user_select_tenants ON tenants
FOR SELECT USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Super users can insert tenants
CREATE POLICY super_user_insert_tenants ON tenants
FOR INSERT WITH CHECK (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Super users can update tenants
CREATE POLICY super_user_update_tenants ON tenants
FOR UPDATE USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Super users can delete tenants
CREATE POLICY super_user_delete_tenants ON tenants
FOR DELETE USING (
  (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Tenant users can view their own non-deleted tenant
CREATE POLICY tenant_user_view_tenants ON tenants
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM tenant_users
    WHERE tenant_users.tenant_id = tenants.id
    AND tenant_users.user_id = auth.uid()
  ) 
  AND is_deleted = FALSE
);

-- Tenant admins can update their own non-deleted tenant
CREATE POLICY tenant_admin_update_tenants ON tenants
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = tenants.id
    AND tenant_user_roles.user_id = auth.uid()
    AND tenant_roles.role_name = 'Admin'
  )
  AND is_deleted = FALSE
);


