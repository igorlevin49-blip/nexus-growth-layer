export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
      activation_reminder_logs: {
        Row: {
          channel: string
          created_at: string | null
          days_before: number
          error_message: string | null
          id: string
          recipient: string
          sent_at: string | null
          sent_date: string
          success: boolean | null
          user_id: string
        }
        Insert: {
          channel: string
          created_at?: string | null
          days_before: number
          error_message?: string | null
          id?: string
          recipient: string
          sent_at?: string | null
          sent_date?: string
          success?: boolean | null
          user_id: string
        }
        Update: {
          channel?: string
          created_at?: string | null
          days_before?: number
          error_message?: string | null
          id?: string
          recipient?: string
          sent_at?: string | null
          sent_date?: string
          success?: boolean | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "activation_reminder_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activation_reminder_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_log: {
        Row: {
          created_at: string
          id: string
          payload: Json | null
          type: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          payload?: Json | null
          type: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          payload?: Json | null
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_log_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_log_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_actions: {
        Row: {
          action_type: string
          admin_id: string
          comment: string | null
          created_at: string
          id: string
          metadata: Json | null
          target_id: string | null
          target_type: string | null
        }
        Insert: {
          action_type: string
          admin_id: string
          comment?: string | null
          created_at?: string
          id?: string
          metadata?: Json | null
          target_id?: string | null
          target_type?: string | null
        }
        Update: {
          action_type?: string
          admin_id?: string
          comment?: string | null
          created_at?: string
          id?: string
          metadata?: Json | null
          target_id?: string | null
          target_type?: string | null
        }
        Relationships: []
      }
      admin_audit: {
        Row: {
          action_type: string
          admin_id: string
          comment: string | null
          created_at: string | null
          id: string
          metadata: Json | null
          target_id: string
          target_type: string
        }
        Insert: {
          action_type: string
          admin_id: string
          comment?: string | null
          created_at?: string | null
          id?: string
          metadata?: Json | null
          target_id: string
          target_type: string
        }
        Update: {
          action_type?: string
          admin_id?: string
          comment?: string | null
          created_at?: string | null
          id?: string
          metadata?: Json | null
          target_id?: string
          target_type?: string
        }
        Relationships: []
      }
      admin_notifications: {
        Row: {
          admin_id: string
          created_at: string
          id: string
          message: string
          metadata: Json | null
          read: boolean
          title: string
          type: string
        }
        Insert: {
          admin_id: string
          created_at?: string
          id?: string
          message: string
          metadata?: Json | null
          read?: boolean
          title: string
          type: string
        }
        Update: {
          admin_id?: string
          created_at?: string
          id?: string
          message?: string
          metadata?: Json | null
          read?: boolean
          title?: string
          type?: string
        }
        Relationships: []
      }
      auto_withdraw_rules: {
        Row: {
          created_at: string
          enabled: boolean | null
          method_id: string | null
          min_amount_cents: number
          schedule: Database["public"]["Enums"]["auto_withdraw_schedule"]
          threshold_cents: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          enabled?: boolean | null
          method_id?: string | null
          min_amount_cents?: number
          schedule?: Database["public"]["Enums"]["auto_withdraw_schedule"]
          threshold_cents?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          enabled?: boolean | null
          method_id?: string | null
          min_amount_cents?: number
          schedule?: Database["public"]["Enums"]["auto_withdraw_schedule"]
          threshold_cents?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "auto_withdraw_rules_method_id_fkey"
            columns: ["method_id"]
            isOneToOne: false
            referencedRelation: "payment_methods"
            referencedColumns: ["id"]
          },
        ]
      }
      commission_plan_levels: {
        Row: {
          created_at: string
          description: string | null
          id: string
          level: number
          percent: number
          plan_id: string
          structure_type: Database["public"]["Enums"]["structure_type"]
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          level: number
          percent: number
          plan_id?: string
          structure_type?: Database["public"]["Enums"]["structure_type"]
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          level?: number
          percent?: number
          plan_id?: string
          structure_type?: Database["public"]["Enums"]["structure_type"]
        }
        Relationships: []
      }
      legal_document_versions: {
        Row: {
          changelog: string | null
          content_md: string
          created_at: string
          created_by: string | null
          document_id: string
          id: string
          version: number
        }
        Insert: {
          changelog?: string | null
          content_md: string
          created_at?: string
          created_by?: string | null
          document_id: string
          id?: string
          version: number
        }
        Update: {
          changelog?: string | null
          content_md?: string
          created_at?: string
          created_by?: string | null
          document_id?: string
          id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "legal_document_versions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_document_versions_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "legal_document_versions_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "legal_documents"
            referencedColumns: ["id"]
          },
        ]
      }
      legal_documents: {
        Row: {
          created_at: string
          current_version_id: string | null
          effective_at: string | null
          id: string
          is_published: boolean
          language: string
          meta_description: string | null
          meta_title: string | null
          og_image_url: string | null
          slug: string
          summary: string | null
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          current_version_id?: string | null
          effective_at?: string | null
          id?: string
          is_published?: boolean
          language?: string
          meta_description?: string | null
          meta_title?: string | null
          og_image_url?: string | null
          slug: string
          summary?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          current_version_id?: string | null
          effective_at?: string | null
          id?: string
          is_published?: boolean
          language?: string
          meta_description?: string | null
          meta_title?: string | null
          og_image_url?: string | null
          slug?: string
          summary?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      mlm_commission_rules: {
        Row: {
          created_at: string
          effective_from: string
          id: string
          is_active: boolean
          level: number
          percent: number
          plan_id: string
          structure_type: number
        }
        Insert: {
          created_at?: string
          effective_from?: string
          id?: string
          is_active?: boolean
          level: number
          percent: number
          plan_id?: string
          structure_type: number
        }
        Update: {
          created_at?: string
          effective_from?: string
          id?: string
          is_active?: boolean
          level?: number
          percent?: number
          plan_id?: string
          structure_type?: number
        }
        Relationships: []
      }
      mlm_settings: {
        Row: {
          description: string | null
          key: string
          updated_at: string | null
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string | null
          value: Json
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string | null
          value?: Json
        }
        Relationships: []
      }
      monthly_activations: {
        Row: {
          admin_comment: string | null
          created_at: string
          id: string
          is_activated: boolean
          last_order_date: string | null
          last_order_id: string | null
          month: number
          period_end: string | null
          period_number: number | null
          period_start: string | null
          threshold_kzt: number
          total_amount_kzt: number
          updated_at: string
          user_id: string
          year: number
        }
        Insert: {
          admin_comment?: string | null
          created_at?: string
          id?: string
          is_activated?: boolean
          last_order_date?: string | null
          last_order_id?: string | null
          month: number
          period_end?: string | null
          period_number?: number | null
          period_start?: string | null
          threshold_kzt?: number
          total_amount_kzt?: number
          updated_at?: string
          user_id: string
          year: number
        }
        Update: {
          admin_comment?: string | null
          created_at?: string
          id?: string
          is_activated?: boolean
          last_order_date?: string | null
          last_order_id?: string | null
          month?: number
          period_end?: string | null
          period_number?: number | null
          period_start?: string | null
          threshold_kzt?: number
          total_amount_kzt?: number
          updated_at?: string
          user_id?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "monthly_activations_last_order_id_fkey"
            columns: ["last_order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "monthly_activations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "monthly_activations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_settings: {
        Row: {
          created_at: string | null
          email_activation_reminder: boolean | null
          email_commissions: boolean | null
          email_new_partner: boolean | null
          email_newsletter: boolean | null
          email_system: boolean | null
          id: string
          sms_enabled: boolean | null
          telegram_enabled: boolean | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string | null
          email_activation_reminder?: boolean | null
          email_commissions?: boolean | null
          email_new_partner?: boolean | null
          email_newsletter?: boolean | null
          email_system?: boolean | null
          id?: string
          sms_enabled?: boolean | null
          telegram_enabled?: boolean | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string | null
          email_activation_reminder?: boolean | null
          email_commissions?: boolean | null
          email_new_partner?: boolean | null
          email_newsletter?: boolean | null
          email_system?: boolean | null
          id?: string
          sms_enabled?: boolean | null
          telegram_enabled?: boolean | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_settings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_settings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      order_items: {
        Row: {
          created_at: string | null
          id: string
          is_activation_snapshot: boolean | null
          order_id: string
          price_kzt: number
          price_usd: number
          product_id: string | null
          qty: number
        }
        Insert: {
          created_at?: string | null
          id?: string
          is_activation_snapshot?: boolean | null
          order_id: string
          price_kzt: number
          price_usd: number
          product_id?: string | null
          qty?: number
        }
        Update: {
          created_at?: string | null
          id?: string
          is_activation_snapshot?: boolean | null
          order_id?: string
          price_kzt?: number
          price_usd?: number
          product_id?: string | null
          qty?: number
        }
        Relationships: [
          {
            foreignKeyName: "order_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      orders: {
        Row: {
          approval_comment: string | null
          approved_by: string | null
          archived_at: string | null
          created_at: string | null
          id: string
          is_archived: boolean | null
          is_test: boolean | null
          paid_at: string | null
          payment_intent_id: string | null
          payment_proof_url: string | null
          payment_type: string | null
          provider_tx_id: string | null
          status: Database["public"]["Enums"]["order_status"] | null
          total_kzt: number
          total_usd: number
          updated_at: string | null
          user_id: string | null
        }
        Insert: {
          approval_comment?: string | null
          approved_by?: string | null
          archived_at?: string | null
          created_at?: string | null
          id?: string
          is_archived?: boolean | null
          is_test?: boolean | null
          paid_at?: string | null
          payment_intent_id?: string | null
          payment_proof_url?: string | null
          payment_type?: string | null
          provider_tx_id?: string | null
          status?: Database["public"]["Enums"]["order_status"] | null
          total_kzt?: number
          total_usd?: number
          updated_at?: string | null
          user_id?: string | null
        }
        Update: {
          approval_comment?: string | null
          approved_by?: string | null
          archived_at?: string | null
          created_at?: string | null
          id?: string
          is_archived?: boolean | null
          is_test?: boolean | null
          paid_at?: string | null
          payment_intent_id?: string | null
          payment_proof_url?: string | null
          payment_type?: string | null
          provider_tx_id?: string | null
          status?: Database["public"]["Enums"]["order_status"] | null
          total_kzt?: number
          total_usd?: number
          updated_at?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      payment_methods: {
        Row: {
          created_at: string
          id: string
          is_default: boolean | null
          masked: string
          meta: Json | null
          type: Database["public"]["Enums"]["payment_method_type"]
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_default?: boolean | null
          masked: string
          meta?: Json | null
          type: Database["public"]["Enums"]["payment_method_type"]
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          is_default?: boolean | null
          masked?: string
          meta?: Json | null
          type?: Database["public"]["Enums"]["payment_method_type"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      product_images: {
        Row: {
          created_at: string | null
          display_order: number | null
          id: string
          is_main: boolean | null
          product_id: string
          storage_path: string
          updated_at: string | null
          url: string
        }
        Insert: {
          created_at?: string | null
          display_order?: number | null
          id?: string
          is_main?: boolean | null
          product_id: string
          storage_path: string
          updated_at?: string | null
          url: string
        }
        Update: {
          created_at?: string | null
          display_order?: number | null
          id?: string
          is_main?: boolean | null
          product_id?: string
          storage_path?: string
          updated_at?: string | null
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "product_images_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "products"
            referencedColumns: ["id"]
          },
        ]
      }
      products: {
        Row: {
          created_at: string | null
          description: string | null
          id: string
          image_url: string | null
          is_activation: boolean | null
          is_new: boolean | null
          is_popular: boolean | null
          price_kzt: number
          price_usd: number
          slug: string
          stock: number | null
          title: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_activation?: boolean | null
          is_new?: boolean | null
          is_popular?: boolean | null
          price_kzt: number
          price_usd: number
          slug: string
          stock?: number | null
          title: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          description?: string | null
          id?: string
          image_url?: string | null
          is_activation?: boolean | null
          is_new?: boolean | null
          is_popular?: boolean | null
          price_kzt?: number
          price_usd?: number
          slug?: string
          stock?: number | null
          title?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          activation_due_from: string | null
          allow_contacts: boolean | null
          avatar_url: string | null
          balance: number | null
          bio: string | null
          created_at: string | null
          deleted_at: string | null
          direct_referrals_count: number | null
          email: string | null
          first_name: string | null
          full_name: string | null
          id: string
          is_active: boolean
          is_archived: boolean | null
          is_public_profile: boolean | null
          is_system_account: boolean | null
          language: string | null
          last_name: string | null
          monthly_activation_completed: boolean | null
          next_activation_date: string | null
          payment_details: string | null
          phone: string | null
          referral_code: string
          referrer_snapshot: Json | null
          show_stats: boolean | null
          sponsor_id: string | null
          subscription_active: boolean | null
          subscription_expires_at: string | null
          subscription_status: string | null
          telegram_chat_id: string | null
          telegram_username: string | null
          timezone: string | null
          updated_at: string | null
        }
        Insert: {
          activation_due_from?: string | null
          allow_contacts?: boolean | null
          avatar_url?: string | null
          balance?: number | null
          bio?: string | null
          created_at?: string | null
          deleted_at?: string | null
          direct_referrals_count?: number | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          id: string
          is_active?: boolean
          is_archived?: boolean | null
          is_public_profile?: boolean | null
          is_system_account?: boolean | null
          language?: string | null
          last_name?: string | null
          monthly_activation_completed?: boolean | null
          next_activation_date?: string | null
          payment_details?: string | null
          phone?: string | null
          referral_code?: string
          referrer_snapshot?: Json | null
          show_stats?: boolean | null
          sponsor_id?: string | null
          subscription_active?: boolean | null
          subscription_expires_at?: string | null
          subscription_status?: string | null
          telegram_chat_id?: string | null
          telegram_username?: string | null
          timezone?: string | null
          updated_at?: string | null
        }
        Update: {
          activation_due_from?: string | null
          allow_contacts?: boolean | null
          avatar_url?: string | null
          balance?: number | null
          bio?: string | null
          created_at?: string | null
          deleted_at?: string | null
          direct_referrals_count?: number | null
          email?: string | null
          first_name?: string | null
          full_name?: string | null
          id?: string
          is_active?: boolean
          is_archived?: boolean | null
          is_public_profile?: boolean | null
          is_system_account?: boolean | null
          language?: string | null
          last_name?: string | null
          monthly_activation_completed?: boolean | null
          next_activation_date?: string | null
          payment_details?: string | null
          phone?: string | null
          referral_code?: string
          referrer_snapshot?: Json | null
          show_stats?: boolean | null
          sponsor_id?: string | null
          subscription_active?: boolean | null
          subscription_expires_at?: string | null
          subscription_status?: string | null
          telegram_chat_id?: string | null
          telegram_username?: string | null
          timezone?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profiles_sponsor_id_fkey"
            columns: ["sponsor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profiles_sponsor_id_fkey"
            columns: ["sponsor_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      referrals: {
        Row: {
          created_at: string
          id: string
          referred_user_id: string
          referrer_id: string
          structure_type: number
          utm_campaign: string | null
          utm_medium: string | null
          utm_source: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          referred_user_id: string
          referrer_id: string
          structure_type?: number
          utm_campaign?: string | null
          utm_medium?: string | null
          utm_source?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          referred_user_id?: string
          referrer_id?: string
          structure_type?: number
          utm_campaign?: string | null
          utm_medium?: string | null
          utm_source?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "referrals_referred_user_id_fkey"
            columns: ["referred_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referrals_referred_user_id_fkey"
            columns: ["referred_user_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referrals_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referrals_referrer_id_fkey"
            columns: ["referrer_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      security_events: {
        Row: {
          created_at: string | null
          id: string
          meta: Json | null
          type: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          meta?: Json | null
          type: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          meta?: Json | null
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "security_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "security_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      shop_settings: {
        Row: {
          currency: Database["public"]["Enums"]["currency_type"] | null
          id: number
          monthly_activation_required_kzt: number | null
          monthly_activation_required_usd: number | null
          rate_usd_kzt: number | null
          updated_at: string | null
        }
        Insert: {
          currency?: Database["public"]["Enums"]["currency_type"] | null
          id?: number
          monthly_activation_required_kzt?: number | null
          monthly_activation_required_usd?: number | null
          rate_usd_kzt?: number | null
          updated_at?: string | null
        }
        Update: {
          currency?: Database["public"]["Enums"]["currency_type"] | null
          id?: number
          monthly_activation_required_kzt?: number | null
          monthly_activation_required_usd?: number | null
          rate_usd_kzt?: number | null
          updated_at?: string | null
        }
        Relationships: []
      }
      subscriptions: {
        Row: {
          admin_comment: string | null
          amount_kzt: number
          amount_usd: number
          approval_comment: string | null
          approved_by: string | null
          archived_at: string | null
          created_at: string
          expires_at: string | null
          id: string
          is_archived: boolean | null
          is_marketing_free_access: boolean | null
          is_test: boolean | null
          paid_at: string | null
          payment_confirmed_at: string | null
          payment_confirmed_by: string | null
          payment_intent_id: string | null
          payment_method: string | null
          payment_proof_url: string | null
          payment_type: string | null
          provider_tx_id: string | null
          started_at: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          admin_comment?: string | null
          amount_kzt: number
          amount_usd: number
          approval_comment?: string | null
          approved_by?: string | null
          archived_at?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          is_archived?: boolean | null
          is_marketing_free_access?: boolean | null
          is_test?: boolean | null
          paid_at?: string | null
          payment_confirmed_at?: string | null
          payment_confirmed_by?: string | null
          payment_intent_id?: string | null
          payment_method?: string | null
          payment_proof_url?: string | null
          payment_type?: string | null
          provider_tx_id?: string | null
          started_at?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          admin_comment?: string | null
          amount_kzt?: number
          amount_usd?: number
          approval_comment?: string | null
          approved_by?: string | null
          archived_at?: string | null
          created_at?: string
          expires_at?: string | null
          id?: string
          is_archived?: boolean | null
          is_marketing_free_access?: boolean | null
          is_test?: boolean | null
          paid_at?: string | null
          payment_confirmed_at?: string | null
          payment_confirmed_by?: string | null
          payment_intent_id?: string | null
          payment_method?: string | null
          payment_proof_url?: string | null
          payment_type?: string | null
          provider_tx_id?: string | null
          started_at?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      system_notification_logs: {
        Row: {
          channel: string
          created_at: string | null
          error_message: string | null
          id: string
          notification_id: string | null
          recipient: string
          success: boolean | null
          user_id: string
        }
        Insert: {
          channel: string
          created_at?: string | null
          error_message?: string | null
          id?: string
          notification_id?: string | null
          recipient: string
          success?: boolean | null
          user_id: string
        }
        Update: {
          channel?: string
          created_at?: string | null
          error_message?: string | null
          id?: string
          notification_id?: string | null
          recipient?: string
          success?: boolean | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "system_notification_logs_notification_id_fkey"
            columns: ["notification_id"]
            isOneToOne: false
            referencedRelation: "system_notifications"
            referencedColumns: ["id"]
          },
        ]
      }
      system_notifications: {
        Row: {
          channels: string[]
          created_at: string | null
          created_by: string | null
          id: string
          message: string
          scheduled_at: string | null
          sent_at: string | null
          status: string
          target_audience: string
          target_user_ids: string[] | null
          title: string
          type: string
          updated_at: string | null
        }
        Insert: {
          channels?: string[]
          created_at?: string | null
          created_by?: string | null
          id?: string
          message: string
          scheduled_at?: string | null
          sent_at?: string | null
          status?: string
          target_audience?: string
          target_user_ids?: string[] | null
          title: string
          type?: string
          updated_at?: string | null
        }
        Update: {
          channels?: string[]
          created_at?: string | null
          created_by?: string | null
          id?: string
          message?: string
          scheduled_at?: string | null
          sent_at?: string | null
          status?: string
          target_audience?: string
          target_user_ids?: string[] | null
          title?: string
          type?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      team_members: {
        Row: {
          created_at: string
          description: string
          display_order: number
          id: string
          is_active: boolean
          name: string
          photo_url: string | null
          position: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description: string
          display_order?: number
          id?: string
          is_active?: boolean
          name: string
          photo_url?: string | null
          position: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string
          display_order?: number
          id?: string
          is_active?: boolean
          name?: string
          photo_url?: string | null
          position?: string
          updated_at?: string
        }
        Relationships: []
      }
      transactions: {
        Row: {
          amount_cents: number
          archived_at: string | null
          created_at: string
          currency: string
          frozen_until: string | null
          id: string
          is_archived: boolean | null
          is_test: boolean | null
          level: number | null
          payload: Json | null
          source_id: string | null
          source_ref: string | null
          status: Database["public"]["Enums"]["transaction_status"]
          structure_type: Database["public"]["Enums"]["structure_type"] | null
          type: Database["public"]["Enums"]["transaction_type"]
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_cents: number
          archived_at?: string | null
          created_at?: string
          currency?: string
          frozen_until?: string | null
          id?: string
          is_archived?: boolean | null
          is_test?: boolean | null
          level?: number | null
          payload?: Json | null
          source_id?: string | null
          source_ref?: string | null
          status?: Database["public"]["Enums"]["transaction_status"]
          structure_type?: Database["public"]["Enums"]["structure_type"] | null
          type: Database["public"]["Enums"]["transaction_type"]
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_cents?: number
          archived_at?: string | null
          created_at?: string
          currency?: string
          frozen_until?: string | null
          id?: string
          is_archived?: boolean | null
          is_test?: boolean | null
          level?: number | null
          payload?: Json | null
          source_id?: string | null
          source_ref?: string | null
          status?: Database["public"]["Enums"]["transaction_status"]
          structure_type?: Database["public"]["Enums"]["structure_type"] | null
          type?: Database["public"]["Enums"]["transaction_type"]
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_consents: {
        Row: {
          accepted_at: string
          document_id: string
          document_version: number
          id: string
          ip: string | null
          user_agent: string | null
          user_id: string
        }
        Insert: {
          accepted_at?: string
          document_id: string
          document_version: number
          id?: string
          ip?: string | null
          user_agent?: string | null
          user_id: string
        }
        Update: {
          accepted_at?: string
          document_id?: string
          document_version?: number
          id?: string
          ip?: string | null
          user_agent?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_consents_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "legal_documents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_consents_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_consents_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      user_modal_notifications: {
        Row: {
          created_at: string | null
          dismissed: boolean | null
          id: string
          message: string
          notification_id: string | null
          read: boolean | null
          show_after: string | null
          title: string
          type: string | null
          user_id: string
        }
        Insert: {
          created_at?: string | null
          dismissed?: boolean | null
          id?: string
          message: string
          notification_id?: string | null
          read?: boolean | null
          show_after?: string | null
          title: string
          type?: string | null
          user_id: string
        }
        Update: {
          created_at?: string | null
          dismissed?: boolean | null
          id?: string
          message?: string
          notification_id?: string | null
          read?: boolean | null
          show_after?: string | null
          title?: string
          type?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_modal_notifications_notification_id_fkey"
            columns: ["notification_id"]
            isOneToOne: false
            referencedRelation: "system_notifications"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string | null
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string | null
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string | null
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
      user_sensitive_data: {
        Row: {
          bank_account: string | null
          card_last_four: string | null
          created_at: string
          id: string
          payment_details_encrypted: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          bank_account?: string | null
          card_last_four?: string | null
          created_at?: string
          id?: string
          payment_details_encrypted?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          bank_account?: string | null
          card_last_four?: string | null
          created_at?: string
          id?: string
          payment_details_encrypted?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_status_achievements: {
        Row: {
          achieved_at: string
          created_at: string
          id: string
          level: number
          shown: boolean
          status_name: string
          user_id: string
        }
        Insert: {
          achieved_at?: string
          created_at?: string
          id?: string
          level: number
          shown?: boolean
          status_name: string
          user_id: string
        }
        Update: {
          achieved_at?: string
          created_at?: string
          id?: string
          level?: number
          shown?: boolean
          status_name?: string
          user_id?: string
        }
        Relationships: []
      }
      withdrawals: {
        Row: {
          amount_cents: number
          archived_at: string | null
          created_at: string
          fee_cents: number
          id: string
          is_archived: boolean | null
          is_test: boolean | null
          method_id: string | null
          processed_at: string | null
          status: Database["public"]["Enums"]["withdrawal_status"]
          transaction_id: string | null
          user_id: string
        }
        Insert: {
          amount_cents: number
          archived_at?: string | null
          created_at?: string
          fee_cents?: number
          id?: string
          is_archived?: boolean | null
          is_test?: boolean | null
          method_id?: string | null
          processed_at?: string | null
          status?: Database["public"]["Enums"]["withdrawal_status"]
          transaction_id?: string | null
          user_id: string
        }
        Update: {
          amount_cents?: number
          archived_at?: string | null
          created_at?: string
          fee_cents?: number
          id?: string
          is_archived?: boolean | null
          is_test?: boolean | null
          method_id?: string | null
          processed_at?: string | null
          status?: Database["public"]["Enums"]["withdrawal_status"]
          transaction_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "withdrawals_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      profiles_network_safe: {
        Row: {
          avatar_url: string | null
          created_at: string | null
          direct_referrals_count: number | null
          full_name: string | null
          id: string | null
          is_active: boolean | null
          monthly_activation_completed: boolean | null
          referral_code: string | null
          sponsor_id: string | null
          subscription_status: string | null
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string | null
          direct_referrals_count?: number | null
          full_name?: string | null
          id?: string | null
          is_active?: boolean | null
          monthly_activation_completed?: boolean | null
          referral_code?: string | null
          sponsor_id?: string | null
          subscription_status?: string | null
        }
        Update: {
          avatar_url?: string | null
          created_at?: string | null
          direct_referrals_count?: number | null
          full_name?: string | null
          id?: string | null
          is_active?: boolean | null
          monthly_activation_completed?: boolean | null
          referral_code?: string | null
          sponsor_id?: string | null
          subscription_status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "profiles_sponsor_id_fkey"
            columns: ["sponsor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "profiles_sponsor_id_fkey"
            columns: ["sponsor_id"]
            isOneToOne: false
            referencedRelation: "profiles_network_safe"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      admin_adjust_balance:
        | {
            Args: {
              p_admin_id: string
              p_amount_kzt: number
              p_reason: string
              p_user_id: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_admin_id: string
              p_amount_cents: number
              p_reason: string
              p_user_id: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_admin_id: string
              p_amount_kzt: number
              p_reason: string
              p_user_id: string
            }
            Returns: Json
          }
      admin_audit_user_commissions: {
        Args: { p_admin_id: string; p_user_id: string }
        Returns: {
          actual_vs_expected: string
          commission_amount_kzt: number
          commission_received: boolean
          expected_commission_kzt: number
          expected_percent: number
          level: number
          no_commission_reason: string
          partner_email: string
          partner_id: string
          partner_name: string
          subscription_amount_kzt: number
          subscription_id: string
        }[]
      }
      admin_backfill_sponsor_from_metadata: { Args: never; Returns: Json }
      admin_bind_sponsor: {
        Args: {
          p_admin_id: string
          p_sponsor_referral_code: string
          p_user_id: string
        }
        Returns: Json
      }
      admin_commission_audit_summary: {
        Args: { p_admin_id: string }
        Returns: Json
      }
      admin_find_early_unlock_commissions: {
        Args: { p_admin_id: string; p_days_back?: number }
        Returns: {
          actual_referrals_at_time: number
          amount_cents: number
          created_at: string
          level: number
          required_referrals: number
          source_id: string
          status: string
          structure_type: string
          subscriber_name: string
          subscription_paid_at: string
          transaction_id: string
          user_id: string
          user_name: string
        }[]
      }
      admin_fix_early_unlock_commissions: {
        Args: { p_admin_id: string; p_days_back?: number; p_dry_run?: boolean }
        Returns: Json
      }
      admin_fix_fractional_commissions: {
        Args: { p_admin_id: string }
        Returns: Json
      }
      admin_fix_marketing_free_violations: {
        Args: { p_admin_id: string; p_dry_run?: boolean }
        Returns: Json
      }
      admin_fix_missing_referrals: { Args: never; Returns: Json }
      admin_fix_unlock_violations: {
        Args: { p_admin_id: string; p_dry_run?: boolean }
        Returns: Json
      }
      admin_recalculate_commissions: {
        Args: never
        Returns: {
          details: Json
          recalculated_orders: number
          recalculated_subscriptions: number
          total_commissions_created: number
        }[]
      }
      admin_referral_backfill: {
        Args: never
        Returns: {
          inserted_referrals: number
          recalculated_direct_counts: number
          updated_sponsor_ids: number
        }[]
      }
      admin_referral_diagnose: {
        Args: never
        Returns: {
          email: string
          issue: string
          user_id: string
        }[]
      }
      approve_activation_order: {
        Args: {
          p_admin_id: string
          p_comment: string
          p_order_id: string
          p_payment_proof_url?: string
        }
        Returns: Json
      }
      approve_subscription_payment: {
        Args: {
          p_admin_id: string
          p_comment: string
          p_payment_proof_url?: string
          p_subscription_id: string
        }
        Returns: Json
      }
      archive_records: {
        Args: { record_ids: string[]; record_type: string }
        Returns: Json
      }
      audit_balance_integrity: {
        Args: never
        Returns: {
          details: Json
          email: string
          issue_type: string
          user_id: string
        }[]
      }
      audit_commission_structure_integrity: {
        Args: never
        Returns: {
          current_structure_type: string
          expected_structure_type: string
          issue: string
          source_ref: string
          transaction_id: string
        }[]
      }
      audit_inactive_partner_commissions: {
        Args: never
        Returns: {
          active_referrals: number
          inactive_referrals: number
          level: number
          potentially_wrong_commissions: number
          required_for_level: number
          total_referrals: number
          user_email: string
          user_id: string
          user_name: string
        }[]
      }
      audit_marketing_free_commissions: {
        Args: never
        Returns: {
          amount_cents: number
          issue: string
          subscriber_name: string
          subscription_id: string
          transaction_id: string
          user_email: string
          user_id: string
        }[]
      }
      audit_unlock_level_violations_detailed: {
        Args: never
        Returns: {
          actual_referrals_at_time: number
          amount_cents: number
          created_at: string
          level: number
          required_referrals: number
          subscriber_id: string
          subscriber_name: string
          subscription_id: string
          transaction_id: string
          user_email: string
          user_id: string
          user_name: string
        }[]
      }
      audit_unlock_levels_violations: {
        Args: never
        Returns: {
          direct_referrals_count: number
          level: number
          required_referrals: number
          total_wrong_amount_cents: number
          user_email: string
          user_id: string
          user_name: string
          violation_count: number
        }[]
      }
      backfill_all_missing_l1_commissions: {
        Args: {
          p_admin_id: string
          p_dry_run?: boolean
          p_target_sponsor_id?: string
        }
        Returns: Json
      }
      backfill_missing_multilevel_commissions:
        | { Args: { p_admin_id: string; p_dry_run?: boolean }; Returns: Json }
        | {
            Args: {
              p_admin_id: string
              p_dry_run?: boolean
              p_target_user_id?: string
            }
            Returns: Json
          }
      backfill_missing_s1_commissions:
        | {
            Args: {
              p_admin_id: string
              p_dry_run?: boolean
              p_sponsor_id?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_admin_id: string
              p_dry_run?: boolean
              p_sponsor_id?: string
            }
            Returns: Json
          }
      backfill_skipped_sponsor_inactive_commissions: {
        Args: { p_admin_id: string; p_dry_run?: boolean }
        Returns: Json
      }
      backfill_sponsor_commissions: {
        Args: { p_admin_id: string; p_dry_run?: boolean; p_sponsor_id: string }
        Returns: Json
      }
      bind_referral: { Args: { p_ref_code: string }; Returns: Json }
      cleanup_all_test_users:
        | {
            Args: {
              p_admin_id: string
              p_confirmation_phrase: string
              p_dry_run?: boolean
            }
            Returns: Json
          }
        | {
            Args: {
              p_admin_id: string
              p_confirmation_phrase: string
              p_dry_run?: boolean
              p_keep_emails: string[]
            }
            Returns: Json
          }
      cleanup_test_data: {
        Args: {
          p_admin_id: string
          p_confirmation_phrase: string
          p_dry_run?: boolean
          p_superadmin_email: string
        }
        Returns: Json
      }
      count_direct_referrals_at_time: {
        Args: { p_at_time: string; p_user_id: string }
        Returns: number
      }
      count_user_referrals: { Args: { p_user_id: string }; Returns: number }
      create_commission_transactions:
        | {
            Args: {
              p_amount_kzt: number
              p_source_id: string
              p_source_ref: string
              p_source_user_id: string
              p_structure_type?: number
            }
            Returns: Json
          }
        | { Args: { p_order_id: string }; Returns: number }
        | {
            Args: {
              p_buyer_id: string
              p_order_amount_kzt: number
              p_order_id: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_amount: number
              p_freeze_days?: number
              p_level: number
              p_order_id: string
              p_recipient_id: string
              p_source_user_id: string
              p_structure_type?: string
            }
            Returns: string
          }
        | {
            Args: {
              p_amount_kzt: number
              p_source_id: string
              p_source_ref: string
              p_source_user_id: string
              p_structure_type?: number
            }
            Returns: Json
          }
        | {
            Args: {
              p_amount_kzt: number
              p_source_id: string
              p_source_ref: string
              p_source_user_id: string
              p_structure_type?: number
            }
            Returns: Json
          }
        | {
            Args: {
              p_amount_kzt: number
              p_source_id: string
              p_source_ref: string
              p_source_user_id: string
              p_structure_type?: number
            }
            Returns: Json
          }
      create_user_withdrawal: {
        Args: { p_amount_kzt: number; p_method_id: string; p_user_id: string }
        Returns: Json
      }
      daily_data_integrity_check: {
        Args: never
        Returns: {
          check_name: string
          description: string
          issue_count: number
          sample_ids: string[]
        }[]
      }
      fix_unlock_level_violations: {
        Args: never
        Returns: {
          details: Json
          fixed_count: number
          total_amount_cents: number
        }[]
      }
      fix_unlock_levels_violations: {
        Args: { p_admin_id: string; p_dry_run?: boolean }
        Returns: Json
      }
      fix_unlock_violations: {
        Args: { dry_run?: boolean }
        Returns: {
          action_taken: string
          amount_cents: number
          level: number
          source_user_id: string
          source_user_name: string
          structure_type: string
          transaction_id: string
          user_id: string
          user_name: string
          violation_reason: string
        }[]
      }
      flag_test_data: {
        Args: {
          p_dry_run?: boolean
          p_end_date: string
          p_start_date: string
          p_user_ids: string[]
        }
        Returns: Json
      }
      get_admin_global_stats: {
        Args: { end_date?: string; start_date?: string }
        Returns: {
          active_users_count: number
          avg_order_cents: number
          frozen_users_count: number
          orders_count: number
          subscriptions_count: number
          total_revenue_cents: number
        }[]
      }
      get_admin_structure_stats: {
        Args: {
          end_date?: string
          start_date?: string
          structure_type_param: number
        }
        Returns: {
          available_amount_cents: number
          frozen_amount_cents: number
          level: number
          pass_up_count: number
          percent: number
          total_amount_cents: number
          transactions_count: number
        }[]
      }
      get_all_user_balances: {
        Args: never
        Returns: {
          available_cents: number
          available_kzt: number
          frozen_cents: number
          frozen_kzt: number
          pending_cents: number
          pending_kzt: number
          user_id: string
          withdrawn_cents: number
          withdrawn_kzt: number
        }[]
      }
      get_commission_structure_stats: {
        Args: {
          p_end_date?: string
          p_start_date?: string
          p_structure_type?: number
          p_user_id: string
        }
        Returns: {
          earned_cents: number
          frozen_cents: number
          level: number
          partners_count: number
          percent: number
          status: string
          unlock_requirement: string
          volume_cents: number
        }[]
      }
      get_monthly_activation_count: {
        Args: {
          p_month: number
          p_search?: string
          p_status?: string
          p_year: number
        }
        Returns: Json
      }
      get_monthly_activation_report:
        | {
            Args: { p_month: number; p_year: number }
            Returns: {
              activation_due_from: string
              email: string
              full_name: string
              is_activated: boolean
              is_grace_period: boolean
              partner_id: string
              period_end: string
              period_number: number
              period_start: string
              subscription_status: string
              threshold_kzt: number
              total_orders: number
              user_id: string
            }[]
          }
        | {
            Args: {
              p_limit?: number
              p_month: number
              p_offset?: number
              p_search?: string
              p_status?: string
              p_year: number
            }
            Returns: {
              activation_due_from: string
              admin_comment: string
              email: string
              full_name: string
              is_activated: boolean
              last_order_date: string
              orders_count: number
              period_end: string
              period_number: number
              period_start: string
              referral_code: string
              threshold_kzt: number
              total_amount_kzt: number
              user_id: string
            }[]
          }
      get_my_sponsor_info: { Args: never; Returns: Json }
      get_network_debug_report: { Args: { p_user_id: string }; Returns: Json }
      get_network_profiles: {
        Args: { p_user_id: string }
        Returns: {
          avatar_url: string
          created_at: string
          direct_referrals_count: number
          full_name: string
          id: string
          is_active: boolean
          monthly_activation_completed: boolean
          referral_code: string
          sponsor_id: string
          subscription_status: string
        }[]
      }
      get_network_stats:
        | {
            Args: { user_id_param: string }
            Returns: {
              activations_this_month: number
              active_partners: number
              commissions_this_month: number
              frozen_partners: number
              max_level: number
              new_this_month: number
              total_partners: number
              volume_this_month: number
            }[]
          }
        | {
            Args: { p_structure_type?: number; user_id_param: string }
            Returns: {
              activations_this_month: number
              active_partners: number
              commissions_this_month: number
              frozen_partners: number
              max_level: number
              new_this_month: number
              total_partners: number
              volume_this_month: number
            }[]
          }
      get_network_tree: {
        Args: { max_level?: number; root_user_id: string }
        Returns: {
          avatar_url: string
          created_at: string
          direct_referrals: number
          email: string
          full_name: string
          level: number
          monthly_activation_met: boolean
          monthly_volume: number
          partner_id: string
          referral_code: string
          subscription_status: string
          total_team: number
          user_id: string
        }[]
      }
      get_partner_orders_for_month: {
        Args: { p_month: number; p_user_id: string; p_year: number }
        Returns: {
          items: Json
          order_date: string
          order_id: string
          status: string
          total_kzt: number
          total_usd: number
        }[]
      }
      get_personal_activation_status: {
        Args: { p_user_id: string }
        Returns: {
          current_amount_kzt: number
          days_remaining: number
          is_activated: boolean
          is_grace_period: boolean
          orders_count: number
          period_end: string
          period_number: number
          period_start: string
          required_amount_kzt: number
        }[]
      }
      get_referral_network: {
        Args: {
          max_levels?: number
          root_user_id: string
          structure_type_param?: number
        }
        Returns: {
          created_at: string
          email: string
          full_name: string
          level: number
          monthly_activation_met: boolean
          partner_id: string
          referral_code: string
          structure_type: number
          subscription_status: string
          user_id: string
        }[]
      }
      get_referral_network_from_table: {
        Args: {
          p_max_levels?: number
          p_structure_type?: number
          root_user_id: string
        }
        Returns: {
          created_at: string
          email: string
          full_name: string
          has_commission_received: boolean
          level: number
          monthly_activation_met: boolean
          no_commission_reason: string
          parent_partner_id: string
          partner_id: string
          referral_code: string
          structure_type: number
          subscription_status: string
          user_id: string
        }[]
      }
      get_sponsors_with_missing_commissions: {
        Args: { p_admin_id: string }
        Returns: {
          missing_amount_kzt: number
          missing_count: number
          partners_count: number
          sponsor_email: string
          sponsor_id: string
          sponsor_name: string
        }[]
      }
      get_user_activation_period: {
        Args: { p_check_date?: string; p_user_id: string }
        Returns: {
          days_remaining: number
          is_grace_period: boolean
          period_end: string
          period_number: number
          period_start: string
        }[]
      }
      get_user_balance: {
        Args: { p_user_id: string }
        Returns: {
          available_cents: number
          available_kzt: number
          frozen_cents: number
          frozen_kzt: number
          pending_cents: number
          pending_kzt: number
          withdrawn_cents: number
          withdrawn_kzt: number
        }[]
      }
      hard_delete_records: {
        Args: {
          confirmation_phrase: string
          dry_run?: boolean
          record_ids: string[]
          record_type: string
        }
        Returns: Json
      }
      hard_delete_user: {
        Args: { p_admin_id: string; p_user_id: string }
        Returns: Json
      }
      has_processing_withdrawal: {
        Args: { p_user_id: string }
        Returns: boolean
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      log_payment_error: {
        Args: {
          p_error_message: string
          p_error_type: string
          p_source_id: string
          p_source_type: string
          p_user_id: string
        }
        Returns: undefined
      }
      process_manual_payout: {
        Args: { p_amount_cents: number; p_comment: string; p_user_id: string }
        Returns: Json
      }
      process_payment_completion: {
        Args: {
          p_admin_id?: string
          p_comment?: string
          p_payment_method?: string
          p_payment_proof_url?: string
          p_provider_tx_id?: string
          p_record_id: string
          p_record_type: string
        }
        Returns: Json
      }
      purge_test_data: {
        Args: { p_confirmation_phrase?: string; p_dry_run?: boolean }
        Returns: Json
      }
      reassign_referrals_to_upper_sponsor: {
        Args: { p_admin_id: string; p_user_id: string }
        Returns: Json
      }
      recalculate_all_s1_commissions: {
        Args: { p_admin_id: string }
        Returns: Json
      }
      recalculate_monthly_activations: {
        Args: { p_admin_id: string; p_month?: number; p_year?: number }
        Returns: Json
      }
      recalculate_user_monthly_activation: {
        Args: { p_month: number; p_user_id: string; p_year: number }
        Returns: undefined
      }
      reconcile_s1_commissions: {
        Args: {
          p_depth?: number
          p_from_date?: string
          p_sponsor_id: string
          p_to_date?: string
        }
        Returns: {
          actual_amount_kzt: number
          actual_status: string
          actual_transaction_id: string
          amount_kzt: number
          expected_commission_kzt: number
          is_marketing_free_access: boolean
          missing_reason: string
          network_level: number
          paid_at: string
          subscriber_email: string
          subscriber_id: string
          subscriber_name: string
          subscription_id: string
          subscription_status: string
        }[]
      }
      reconcile_s1_commissions_summary: {
        Args: {
          p_depth?: number
          p_from_date?: string
          p_sponsor_id: string
          p_to_date?: string
        }
        Returns: {
          actual_total_kzt: number
          difference_kzt: number
          expected_total_kzt: number
          marketing_free_count: number
          missing_commission: number
          missing_reasons: Json
          paid_subscriptions: number
          total_subscriptions: number
          with_commission: number
        }[]
      }
      reject_payment: {
        Args: {
          p_admin_id: string
          p_comment: string
          p_record_id: string
          p_record_type: string
        }
        Returns: Json
      }
      release_expired_frozen_transactions: { Args: never; Returns: Json }
      reset_monthly_activation_status: { Args: never; Returns: undefined }
      reset_personal_activations: {
        Args: never
        Returns: {
          full_name: string
          new_period: number
          old_period: number
          user_id: string
        }[]
      }
      restore_user: {
        Args: { p_admin_id: string; p_user_id: string }
        Returns: Json
      }
      reverse_marketing_free_commissions: {
        Args: {
          p_admin_id: string
          p_comment?: string
          p_source_user_id: string
        }
        Returns: Json
      }
      reverse_unlock_level_violations: {
        Args: { p_admin_id: string; p_dry_run?: boolean }
        Returns: Json
      }
      run_critical_tests_or_fail: { Args: never; Returns: undefined }
      run_post_migration_tests: {
        Args: never
        Returns: {
          category: string
          details: Json
          error_message: string
          is_critical: boolean
          passed: boolean
          test_name: string
        }[]
      }
      soft_delete_user: {
        Args: { p_admin_id: string; p_user_id: string }
        Returns: Json
      }
      validate_referral_code: { Args: { p_ref_code: string }; Returns: Json }
    }
    Enums: {
      app_role: "user" | "admin" | "superadmin"
      auto_withdraw_schedule: "daily" | "weekly" | "monthly"
      currency_type: "USD" | "KZT"
      order_status: "draft" | "pending" | "paid" | "cancelled"
      payment_method_type: "card" | "bank" | "crypto" | "other" | "cash"
      structure_type: "primary" | "secondary"
      transaction_status:
        | "pending"
        | "processing"
        | "completed"
        | "failed"
        | "frozen"
      transaction_type:
        | "commission"
        | "bonus"
        | "withdrawal"
        | "adjustment"
        | "purchase"
      withdrawal_status:
        | "pending"
        | "processing"
        | "completed"
        | "failed"
        | "cancelled"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["user", "admin", "superadmin"],
      auto_withdraw_schedule: ["daily", "weekly", "monthly"],
      currency_type: ["USD", "KZT"],
      order_status: ["draft", "pending", "paid", "cancelled"],
      payment_method_type: ["card", "bank", "crypto", "other", "cash"],
      structure_type: ["primary", "secondary"],
      transaction_status: [
        "pending",
        "processing",
        "completed",
        "failed",
        "frozen",
      ],
      transaction_type: [
        "commission",
        "bonus",
        "withdrawal",
        "adjustment",
        "purchase",
      ],
      withdrawal_status: [
        "pending",
        "processing",
        "completed",
        "failed",
        "cancelled",
      ],
    },
  },
} as const
