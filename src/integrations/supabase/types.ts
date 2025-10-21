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
            referencedRelation: "user_balances"
            referencedColumns: ["user_id"]
          },
        ]
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
          created_at: string | null
          id: string
          status: Database["public"]["Enums"]["order_status"] | null
          total_kzt: number
          total_usd: number
          updated_at: string | null
          user_id: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          status?: Database["public"]["Enums"]["order_status"] | null
          total_kzt?: number
          total_usd?: number
          updated_at?: string | null
          user_id?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
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
          avatar_url: string | null
          balance: number | null
          created_at: string | null
          email: string | null
          full_name: string | null
          id: string
          monthly_activation_completed: boolean | null
          next_activation_date: string | null
          payment_details: string | null
          phone: string | null
          referral_code: string
          sponsor_id: string | null
          subscription_expires_at: string | null
          subscription_status: string | null
          telegram_username: string | null
          updated_at: string | null
        }
        Insert: {
          avatar_url?: string | null
          balance?: number | null
          created_at?: string | null
          email?: string | null
          full_name?: string | null
          id: string
          monthly_activation_completed?: boolean | null
          next_activation_date?: string | null
          payment_details?: string | null
          phone?: string | null
          referral_code?: string
          sponsor_id?: string | null
          subscription_expires_at?: string | null
          subscription_status?: string | null
          telegram_username?: string | null
          updated_at?: string | null
        }
        Update: {
          avatar_url?: string | null
          balance?: number | null
          created_at?: string | null
          email?: string | null
          full_name?: string | null
          id?: string
          monthly_activation_completed?: boolean | null
          next_activation_date?: string | null
          payment_details?: string | null
          phone?: string | null
          referral_code?: string
          sponsor_id?: string | null
          subscription_expires_at?: string | null
          subscription_status?: string | null
          telegram_username?: string | null
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
            referencedRelation: "user_balances"
            referencedColumns: ["user_id"]
          },
        ]
      }
      shop_settings: {
        Row: {
          currency: Database["public"]["Enums"]["currency_type"] | null
          id: number
          monthly_activation_required_usd: number | null
          rate_usd_kzt: number | null
          updated_at: string | null
        }
        Insert: {
          currency?: Database["public"]["Enums"]["currency_type"] | null
          id?: number
          monthly_activation_required_usd?: number | null
          rate_usd_kzt?: number | null
          updated_at?: string | null
        }
        Update: {
          currency?: Database["public"]["Enums"]["currency_type"] | null
          id?: number
          monthly_activation_required_usd?: number | null
          rate_usd_kzt?: number | null
          updated_at?: string | null
        }
        Relationships: []
      }
      transactions: {
        Row: {
          amount_cents: number
          created_at: string
          currency: string
          frozen_until: string | null
          id: string
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
          created_at?: string
          currency?: string
          frozen_until?: string | null
          id?: string
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
          created_at?: string
          currency?: string
          frozen_until?: string | null
          id?: string
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
            referencedRelation: "user_balances"
            referencedColumns: ["user_id"]
          },
        ]
      }
      withdrawals: {
        Row: {
          amount_cents: number
          created_at: string
          fee_cents: number
          id: string
          method_id: string | null
          processed_at: string | null
          status: Database["public"]["Enums"]["withdrawal_status"]
          transaction_id: string | null
          user_id: string
        }
        Insert: {
          amount_cents: number
          created_at?: string
          fee_cents?: number
          id?: string
          method_id?: string | null
          processed_at?: string | null
          status?: Database["public"]["Enums"]["withdrawal_status"]
          transaction_id?: string | null
          user_id: string
        }
        Update: {
          amount_cents?: number
          created_at?: string
          fee_cents?: number
          id?: string
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
      user_balances: {
        Row: {
          available_cents: number | null
          frozen_cents: number | null
          pending_cents: number | null
          updated_at: string | null
          user_id: string | null
          withdrawn_cents: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      get_network_stats: {
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
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
    }
    Enums: {
      app_role: "user" | "admin" | "superadmin"
      auto_withdraw_schedule: "daily" | "weekly" | "monthly"
      currency_type: "USD" | "KZT"
      order_status: "draft" | "pending" | "paid" | "cancelled"
      payment_method_type: "card" | "bank" | "crypto" | "other"
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
      payment_method_type: ["card", "bank", "crypto", "other"],
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
