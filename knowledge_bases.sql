CREATE TABLE knowledge_bases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  is_public BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_knowledge_bases_tenant_id ON knowledge_bases(tenant_id);

-- Create trigger for automatic updated_at timestamp updates
-- Note: Reusing the existing update_timestamp() function
CREATE TRIGGER set_timestamp
BEFORE UPDATE ON knowledge_bases
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();

-- Enable Row Level Security
ALTER TABLE knowledge_bases ENABLE ROW LEVEL SECURITY;

-- Users can access public KBs in their tenants
CREATE POLICY access_public_kb ON knowledge_bases
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM tenant_users
    WHERE tenant_users.tenant_id = knowledge_bases.tenant_id
    AND tenant_users.user_id = auth.uid()
    AND tenant_users.is_active = TRUE
  ) AND is_public = TRUE
);

-- Users can access KBs based on their roles
CREATE POLICY access_role_based_kb ON knowledge_bases
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM kb_role_access
    WHERE kb_role_access.kb_id = knowledge_bases.id
    AND kb_role_access.role_id IN (
      SELECT role_id FROM tenant_user_roles
      WHERE tenant_user_roles.user_id = auth.uid()
      AND tenant_user_roles.tenant_id = knowledge_bases.tenant_id
    )
  )
);

-- Super users can manage all KBs - IMPROVED with EXISTS and WITH CHECK
CREATE POLICY super_user_manage_kb ON knowledge_bases
FOR ALL 
USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
)
WITH CHECK (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
);

-- Tenant admins can manage KBs in their tenant - IMPROVED to avoid hardcoding and be more flexible
CREATE POLICY tenant_admin_manage_kb ON knowledge_bases
FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = knowledge_bases.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND (
      tenant_roles.role_name = 'Admin' OR tenant_roles.is_system_role = TRUE
    )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = knowledge_bases.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND (
      tenant_roles.role_name = 'Admin' OR tenant_roles.is_system_role = TRUE
    )
  )
);
