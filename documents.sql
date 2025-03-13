
CREATE TABLE IF NOT EXISTS kb_document (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kb_id UUID NOT NULL REFERENCES knowledge_bases(id) ON DELETE CASCADE,
  content TEXT NULL,
  metadata JSONB NULL,
  embedding extensions.vector NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Only essential indexes
CREATE INDEX IF NOT EXISTS idx_kb_document_chunks_tenant_id ON kb_document_chunks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_kb_document_chunks_kb_id ON kb_document_chunks(kb_id);

-- Enable RLS
ALTER TABLE kb_document_chunks ENABLE ROW LEVEL SECURITY;

-- Basic tenant isolation policy
CREATE POLICY tenant_isolation_chunks ON kb_document_chunks
FOR ALL USING (
  tenant_id = current_setting('app.current_tenant_id', TRUE)::UUID
  OR (SELECT is_super_user FROM user_profiles WHERE id = auth.uid())
);

-- Knowledge base access policy
CREATE POLICY kb_access_chunks ON kb_document_chunks
FOR SELECT USING (
  -- Allow if KB is public
  EXISTS (
    SELECT 1 FROM knowledge_bases 
    WHERE knowledge_bases.id = kb_document_chunks.kb_id
    AND knowledge_bases.is_public = TRUE
  )
  -- Or if user has role-based access
  OR EXISTS (
    SELECT 1 FROM kb_role_access
    WHERE kb_role_access.kb_id = kb_document_chunks.kb_id
    AND kb_role_access.role_id IN (
      SELECT role_id FROM tenant_user_roles
      WHERE tenant_user_roles.user_id = auth.uid()
      AND tenant_user_roles.tenant_id = kb_document_chunks.tenant_id
    )
  )
);
