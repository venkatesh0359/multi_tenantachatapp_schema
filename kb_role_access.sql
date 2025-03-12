CREATE TABLE kb_role_access (
  kb_id UUID REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  role_id UUID REFERENCES tenant_roles(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (kb_id, role_id)
);

-- Create indexes
CREATE INDEX idx_kb_role_access_tenant_id ON kb_role_access(tenant_id);
CREATE INDEX idx_kb_role_access_role_id ON kb_role_access(role_id);

-- Enable Row Level Security
ALTER TABLE kb_role_access ENABLE ROW LEVEL SECURITY;

-- Users can view KB access settings for their tenants
CREATE POLICY view_kb_access ON kb_role_access
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM tenant_users
    WHERE tenant_users.tenant_id = kb_role_access.tenant_id
    AND tenant_users.user_id = auth.uid()
    AND tenant_users.is_active = TRUE
  )
);

-- Super users can manage all KB access - IMPROVED with EXISTS and WITH CHECK
CREATE POLICY super_user_manage_kb_access ON kb_role_access
FOR ALL 
USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
)
WITH CHECK (
  EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND is_super_user = TRUE)
);

-- Tenant admins can manage KB access for their tenant - IMPROVED with WITH CHECK and role flexibility
CREATE POLICY tenant_admin_manage_kb_access ON kb_role_access
FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM tenant_user_roles
    JOIN tenant_roles ON tenant_roles.id = tenant_user_roles.role_id
    WHERE tenant_user_roles.tenant_id = kb_role_access.tenant_id
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
    WHERE tenant_user_roles.tenant_id = kb_role_access.tenant_id
    AND tenant_user_roles.user_id = auth.uid()
    AND (
      tenant_roles.role_name = 'Admin' OR tenant_roles.is_system_role = TRUE
    )
  )
);
