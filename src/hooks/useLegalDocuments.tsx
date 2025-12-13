import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export const useLegalDocuments = (language = 'ru') => {
  return useQuery({
    queryKey: ['legal-documents', language],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('legal_documents')
        .select('*')
        .eq('language', language)
        .eq('is_published', true)
        .order('effective_at', { ascending: false });
      
      if (error) throw error;
      return data;
    },
  });
};

export const useLegalDocument = (slug: string) => {
  return useQuery({
    queryKey: ['legal-document', slug],
    queryFn: async () => {
      const { data: doc, error: docError } = await supabase
        .from('legal_documents')
        .select('*, current_version_id')
        .eq('slug', slug)
        .eq('is_published', true)
        .single();
      
      if (docError) throw docError;
      
      if (doc.current_version_id) {
        const { data: version, error: versionError } = await supabase
          .from('legal_document_versions')
          .select('*')
          .eq('id', doc.current_version_id)
          .single();
        
        if (versionError) throw versionError;
        
        return { ...doc, currentVersion: version };
      }
      
      return doc;
    },
  });
};

export const useAdminLegalDocuments = () => {
  return useQuery({
    queryKey: ['admin-legal-documents'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('legal_documents')
        .select('*')
        .order('created_at', { ascending: false });
      
      if (error) throw error;
      return data;
    },
  });
};

export const useDocumentVersions = (documentId: string) => {
  return useQuery({
    queryKey: ['document-versions', documentId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('legal_document_versions')
        .select('*')
        .eq('document_id', documentId)
        .order('version', { ascending: false });
      
      if (error) throw error;
      return data;
    },
    enabled: !!documentId,
  });
};

export const useCreateDocument = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (data: any) => {
      const { data: doc, error } = await supabase
        .from('legal_documents')
        .insert(data)
        .select()
        .single();
      
      if (error) throw error;
      return doc;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-legal-documents'] });
      toast.success('Документ создан');
    },
    onError: () => {
      toast.error('Ошибка при создании документа');
    },
  });
};

export const useUpdateDocument = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, data }: { id: string; data: any }) => {
      const { error } = await supabase
        .from('legal_documents')
        .update(data)
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-legal-documents'] });
      toast.success('Документ обновлён');
    },
    onError: () => {
      toast.error('Ошибка при обновлении документа');
    },
  });
};

export const useCreateVersion = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (data: any) => {
      const { data: session } = await supabase.auth.getSession();
      
      const { data: version, error } = await supabase
        .from('legal_document_versions')
        .insert({
          ...data,
          created_by: session.session?.user.id,
        })
        .select()
        .single();
      
      if (error) throw error;
      return version;
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['document-versions', variables.document_id] });
      toast.success('Версия создана');
    },
    onError: () => {
      toast.error('Ошибка при создании версии');
    },
  });
};

export const useRecordConsent = () => {
  return useMutation({
    mutationFn: async (data: { document_id: string; document_version: number }) => {
      const { data: session } = await supabase.auth.getSession();
      
      const { error } = await supabase
        .from('user_consents')
        .insert({
          user_id: session.session?.user.id,
          document_id: data.document_id,
          document_version: data.document_version,
        });
      
      if (error) throw error;
    },
  });
};

export const useDeleteDocument = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: string) => {
      // Сначала удаляем все версии документа
      const { error: versionsError } = await supabase
        .from('legal_document_versions')
        .delete()
        .eq('document_id', id);
      
      if (versionsError) throw versionsError;
      
      // Затем удаляем сам документ
      const { error } = await supabase
        .from('legal_documents')
        .delete()
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-legal-documents'] });
      toast.success('Документ удалён');
    },
    onError: () => {
      toast.error('Ошибка при удалении документа');
    },
  });
};

export const useUpdateVersion = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, data }: { id: string; data: { content_md?: string; changelog?: string } }) => {
      const { error } = await supabase
        .from('legal_document_versions')
        .update(data)
        .eq('id', id);
      
      if (error) throw error;
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['document-versions'] });
      toast.success('Версия обновлена');
    },
    onError: () => {
      toast.error('Ошибка при обновлении версии');
    },
  });
};

export const useDeleteVersion = () => {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async ({ id, documentId }: { id: string; documentId: string }) => {
      const { error } = await supabase
        .from('legal_document_versions')
        .delete()
        .eq('id', id);
      
      if (error) throw error;
      
      return documentId;
    },
    onSuccess: (documentId) => {
      queryClient.invalidateQueries({ queryKey: ['document-versions', documentId] });
      toast.success('Версия удалена');
    },
    onError: () => {
      toast.error('Ошибка при удалении версии');
    },
  });
};