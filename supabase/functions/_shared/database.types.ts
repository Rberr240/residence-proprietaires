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
    PostgrestVersion: "14.15"
  }
  public: {
    Tables: {
      access_codes: {
        Row: {
          active: boolean
          apartment_id: string
          code_hash: string
          created_at: string
          expires_at: string | null
          id: string
          used_at: string | null
        }
        Insert: {
          active?: boolean
          apartment_id: string
          code_hash: string
          created_at?: string
          expires_at?: string | null
          id?: string
          used_at?: string | null
        }
        Update: {
          active?: boolean
          apartment_id?: string
          code_hash?: string
          created_at?: string
          expires_at?: string | null
          id?: string
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "access_codes_apartment_id_fkey"
            columns: ["apartment_id"]
            isOneToOne: false
            referencedRelation: "apartments"
            referencedColumns: ["id"]
          },
        ]
      }
      admin_users: {
        Row: {
          auth_user_id: string
          created_at: string
          display_name: string | null
          id: string
          is_active: boolean
          role: string
        }
        Insert: {
          auth_user_id: string
          created_at?: string
          display_name?: string | null
          id?: string
          is_active?: boolean
          role?: string
        }
        Update: {
          auth_user_id?: string
          created_at?: string
          display_name?: string | null
          id?: string
          is_active?: boolean
          role?: string
        }
        Relationships: []
      }
      apartments: {
        Row: {
          apartment_number: string
          building_id: string
          created_at: string
          floor: number | null
          id: string
        }
        Insert: {
          apartment_number: string
          building_id: string
          created_at?: string
          floor?: number | null
          id?: string
        }
        Update: {
          apartment_number?: string
          building_id?: string
          created_at?: string
          floor?: number | null
          id?: string
        }
        Relationships: [
          {
            foreignKeyName: "apartments_building_id_fkey"
            columns: ["building_id"]
            isOneToOne: false
            referencedRelation: "buildings"
            referencedColumns: ["id"]
          },
        ]
      }
      buildings: {
        Row: {
          active: boolean
          apartment_count: number | null
          code: string
          created_at: string
          id: string
          name: string
          type: string
          updated_at: string
        }
        Insert: {
          active?: boolean
          apartment_count?: number | null
          code: string
          created_at?: string
          id?: string
          name: string
          type: string
          updated_at?: string
        }
        Update: {
          active?: boolean
          apartment_count?: number | null
          code?: string
          created_at?: string
          id?: string
          name?: string
          type?: string
          updated_at?: string
        }
        Relationships: []
      }
      meeting_responses: {
        Row: {
          attendance: string | null
          availability: string[]
          created_at: string
          id: string
          meeting_id: string
          owner_id: string
          subject: string | null
          updated_at: string
        }
        Insert: {
          attendance?: string | null
          availability?: string[]
          created_at?: string
          id?: string
          meeting_id: string
          owner_id: string
          subject?: string | null
          updated_at?: string
        }
        Update: {
          attendance?: string | null
          availability?: string[]
          created_at?: string
          id?: string
          meeting_id?: string
          owner_id?: string
          subject?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meeting_responses_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "meetings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_responses_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "owners"
            referencedColumns: ["id"]
          },
        ]
      }
      meetings: {
        Row: {
          closed_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          location: string | null
          meeting_date: string | null
          published_at: string | null
          response_deadline: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          location?: string | null
          meeting_date?: string | null
          published_at?: string | null
          response_deadline?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          location?: string | null
          meeting_date?: string | null
          published_at?: string | null
          response_deadline?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      owner_account_units: {
        Row: {
          apartment_number: string
          building_code: string
          created_at: string
          id: string
          is_primary: boolean
          owner_account_id: string
          submission_id: string
        }
        Insert: {
          apartment_number: string
          building_code: string
          created_at?: string
          id?: string
          is_primary?: boolean
          owner_account_id: string
          submission_id: string
        }
        Update: {
          apartment_number?: string
          building_code?: string
          created_at?: string
          id?: string
          is_primary?: boolean
          owner_account_id?: string
          submission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "owner_account_units_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "owner_account_units_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: true
            referencedRelation: "owner_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      owner_accounts: {
        Row: {
          activated_at: string | null
          auth_user_id: string | null
          created_at: string
          email: string | null
          first_name: string
          id: string
          last_name: string
          phone: string
          phone_e164: string | null
          status: string
          whatsapp: string | null
        }
        Insert: {
          activated_at?: string | null
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          first_name: string
          id?: string
          last_name: string
          phone: string
          phone_e164?: string | null
          status?: string
          whatsapp?: string | null
        }
        Update: {
          activated_at?: string | null
          auth_user_id?: string | null
          created_at?: string
          email?: string | null
          first_name?: string
          id?: string
          last_name?: string
          phone?: string
          phone_e164?: string | null
          status?: string
          whatsapp?: string | null
        }
        Relationships: []
      }
      owner_activation_codes: {
        Row: {
          code_hash: string
          created_at: string
          expires_at: string
          id: string
          owner_account_id: string
          revoked_at: string | null
          used_at: string | null
        }
        Insert: {
          code_hash: string
          created_at?: string
          expires_at: string
          id?: string
          owner_account_id: string
          revoked_at?: string | null
          used_at?: string | null
        }
        Update: {
          code_hash?: string
          created_at?: string
          expires_at?: string
          id?: string
          owner_account_id?: string
          revoked_at?: string | null
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "owner_activation_codes_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      owner_meeting_responses: {
        Row: {
          attendance: string
          comment: string | null
          created_at: string
          id: string
          meeting_id: string
          owner_account_id: string
          responded_at: string
          updated_at: string
        }
        Insert: {
          attendance: string
          comment?: string | null
          created_at?: string
          id?: string
          meeting_id: string
          owner_account_id: string
          responded_at?: string
          updated_at?: string
        }
        Update: {
          attendance?: string
          comment?: string | null
          created_at?: string
          id?: string
          meeting_id?: string
          owner_account_id?: string
          responded_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "owner_meeting_responses_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "meetings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "owner_meeting_responses_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      owner_submissions: {
        Row: {
          apartment_number: string
          attendance: string | null
          availability: string[]
          building_code: string
          cin: string | null
          consent: boolean
          created_at: string
          email: string | null
          first_name: string
          id: string
          last_name: string
          phone: string
          status: string
          subject: string | null
          whatsapp: string | null
        }
        Insert: {
          apartment_number: string
          attendance?: string | null
          availability?: string[]
          building_code: string
          cin?: string | null
          consent: boolean
          created_at?: string
          email?: string | null
          first_name: string
          id?: string
          last_name: string
          phone: string
          status?: string
          subject?: string | null
          whatsapp?: string | null
        }
        Update: {
          apartment_number?: string
          attendance?: string | null
          availability?: string[]
          building_code?: string
          cin?: string | null
          consent?: boolean
          created_at?: string
          email?: string | null
          first_name?: string
          id?: string
          last_name?: string
          phone?: string
          status?: string
          subject?: string | null
          whatsapp?: string | null
        }
        Relationships: []
      }
      owner_vote_ballots: {
        Row: {
          id: string
          option_id: string
          owner_account_id: string
          submitted_at: string
          updated_at: string
          vote_id: string
        }
        Insert: {
          id?: string
          option_id: string
          owner_account_id: string
          submitted_at?: string
          updated_at?: string
          vote_id: string
        }
        Update: {
          id?: string
          option_id?: string
          owner_account_id?: string
          submitted_at?: string
          updated_at?: string
          vote_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "owner_vote_ballots_eligibility_fkey"
            columns: ["vote_id", "owner_account_id"]
            isOneToOne: true
            referencedRelation: "residence_vote_eligibility"
            referencedColumns: ["vote_id", "owner_account_id"]
          },
          {
            foreignKeyName: "owner_vote_ballots_option_fkey"
            columns: ["vote_id", "option_id"]
            isOneToOne: false
            referencedRelation: "residence_vote_options"
            referencedColumns: ["vote_id", "id"]
          },
        ]
      }
      owners: {
        Row: {
          apartment_id: string
          consent: boolean
          consent_at: string | null
          created_at: string
          email: string | null
          first_name: string
          id: string
          last_name: string
          phone: string
          updated_at: string
          verified: boolean
          whatsapp: string | null
        }
        Insert: {
          apartment_id: string
          consent?: boolean
          consent_at?: string | null
          created_at?: string
          email?: string | null
          first_name: string
          id?: string
          last_name: string
          phone: string
          updated_at?: string
          verified?: boolean
          whatsapp?: string | null
        }
        Update: {
          apartment_id?: string
          consent?: boolean
          consent_at?: string | null
          created_at?: string
          email?: string | null
          first_name?: string
          id?: string
          last_name?: string
          phone?: string
          updated_at?: string
          verified?: boolean
          whatsapp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "owners_apartment_id_fkey"
            columns: ["apartment_id"]
            isOneToOne: false
            referencedRelation: "apartments"
            referencedColumns: ["id"]
          },
        ]
      }
      registration_sessions: {
        Row: {
          access_code_id: string
          apartment_id: string
          consumed_at: string | null
          created_at: string
          expires_at: string
          id: string
          token_hash: string
        }
        Insert: {
          access_code_id: string
          apartment_id: string
          consumed_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          token_hash: string
        }
        Update: {
          access_code_id?: string
          apartment_id?: string
          consumed_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "registration_sessions_access_code_id_fkey"
            columns: ["access_code_id"]
            isOneToOne: false
            referencedRelation: "access_codes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "registration_sessions_apartment_id_fkey"
            columns: ["apartment_id"]
            isOneToOne: false
            referencedRelation: "apartments"
            referencedColumns: ["id"]
          },
        ]
      }
      residence_vote_eligibility: {
        Row: {
          created_at: string
          id: string
          owner_account_id: string
          vote_id: string
          voting_weight: number
        }
        Insert: {
          created_at?: string
          id?: string
          owner_account_id: string
          vote_id: string
          voting_weight?: number
        }
        Update: {
          created_at?: string
          id?: string
          owner_account_id?: string
          vote_id?: string
          voting_weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "residence_vote_eligibility_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "residence_vote_eligibility_vote_id_fkey"
            columns: ["vote_id"]
            isOneToOne: false
            referencedRelation: "residence_votes"
            referencedColumns: ["id"]
          },
        ]
      }
      residence_vote_options: {
        Row: {
          created_at: string
          description: string | null
          id: string
          label: string
          position: number
          vote_id: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          label: string
          position?: number
          vote_id: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          label?: string
          position?: number
          vote_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "residence_vote_options_vote_id_fkey"
            columns: ["vote_id"]
            isOneToOne: false
            referencedRelation: "residence_votes"
            referencedColumns: ["id"]
          },
        ]
      }
      residence_votes: {
        Row: {
          allow_vote_change: boolean
          cancelled_at: string | null
          closed_at: string | null
          closes_at: string | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          opens_at: string | null
          published_at: string | null
          question: string
          results_visibility: string
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          allow_vote_change?: boolean
          cancelled_at?: string | null
          closed_at?: string | null
          closes_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          opens_at?: string | null
          published_at?: string | null
          question: string
          results_visibility?: string
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          allow_vote_change?: boolean
          cancelled_at?: string | null
          closed_at?: string | null
          closes_at?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          opens_at?: string | null
          published_at?: string | null
          question?: string
          results_visibility?: string
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      syndic_charge_calls: {
        Row: {
          cancelled_at: string | null
          charge_type: string
          closed_at: string | null
          created_at: string
          created_by: string | null
          currency: string
          default_amount: number
          description: string | null
          due_date: string
          fiscal_year: number
          id: string
          period_label: string | null
          published_at: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          cancelled_at?: string | null
          charge_type?: string
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          default_amount: number
          description?: string | null
          due_date: string
          fiscal_year: number
          id?: string
          period_label?: string | null
          published_at?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          cancelled_at?: string | null
          charge_type?: string
          closed_at?: string | null
          created_at?: string
          created_by?: string | null
          currency?: string
          default_amount?: number
          description?: string | null
          due_date?: string
          fiscal_year?: number
          id?: string
          period_label?: string | null
          published_at?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      syndic_payment_allocations: {
        Row: {
          amount: number
          created_at: string
          id: string
          payment_id: string
          unit_charge_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          payment_id: string
          unit_charge_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          payment_id?: string
          unit_charge_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "syndic_payment_allocations_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "syndic_payments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "syndic_payment_allocations_unit_charge_id_fkey"
            columns: ["unit_charge_id"]
            isOneToOne: false
            referencedRelation: "syndic_unit_charges"
            referencedColumns: ["id"]
          },
        ]
      }
      syndic_payments: {
        Row: {
          amount: number
          confirmed_at: string | null
          created_at: string
          currency: string
          id: string
          notes: string | null
          owner_account_id: string
          payment_date: string
          payment_method: string
          receipt_storage_path: string | null
          recorded_by: string | null
          reference: string | null
          reversal_reason: string | null
          reversed_at: string | null
          reversed_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount: number
          confirmed_at?: string | null
          created_at?: string
          currency?: string
          id?: string
          notes?: string | null
          owner_account_id: string
          payment_date: string
          payment_method: string
          receipt_storage_path?: string | null
          recorded_by?: string | null
          reference?: string | null
          reversal_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount?: number
          confirmed_at?: string | null
          created_at?: string
          currency?: string
          id?: string
          notes?: string | null
          owner_account_id?: string
          payment_date?: string
          payment_method?: string
          receipt_storage_path?: string | null
          recorded_by?: string | null
          reference?: string | null
          reversal_reason?: string | null
          reversed_at?: string | null
          reversed_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "syndic_payments_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      syndic_unit_charges: {
        Row: {
          adjustment_amount: number
          adjustment_note: string | null
          amount_due: number | null
          apartment_number: string
          base_amount: number
          building_code: string
          charge_call_id: string
          created_at: string
          id: string
          owner_account_id: string
          owner_account_unit_id: string
          updated_at: string
        }
        Insert: {
          adjustment_amount?: number
          adjustment_note?: string | null
          amount_due?: number | null
          apartment_number: string
          base_amount: number
          building_code: string
          charge_call_id: string
          created_at?: string
          id?: string
          owner_account_id: string
          owner_account_unit_id: string
          updated_at?: string
        }
        Update: {
          adjustment_amount?: number
          adjustment_note?: string | null
          amount_due?: number | null
          apartment_number?: string
          base_amount?: number
          building_code?: string
          charge_call_id?: string
          created_at?: string
          id?: string
          owner_account_id?: string
          owner_account_unit_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "syndic_unit_charges_charge_call_id_fkey"
            columns: ["charge_call_id"]
            isOneToOne: false
            referencedRelation: "syndic_charge_calls"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "syndic_unit_charges_owner_account_id_fkey"
            columns: ["owner_account_id"]
            isOneToOne: false
            referencedRelation: "owner_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "syndic_unit_charges_owner_account_unit_id_fkey"
            columns: ["owner_account_unit_id"]
            isOneToOne: false
            referencedRelation: "owner_account_units"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      admin_cancel_residence_vote: {
        Args: { p_vote_id: string }
        Returns: Json
      }
      admin_cancel_syndic_charge_call: {
        Args: { p_charge_call_id: string }
        Returns: Json
      }
      admin_close_residence_vote: { Args: { p_vote_id: string }; Returns: Json }
      admin_close_syndic_charge_call: {
        Args: { p_charge_call_id: string }
        Returns: Json
      }
      admin_get_meeting_stats: { Args: { p_meeting_id: string }; Returns: Json }
      admin_get_residence_vote_stats: {
        Args: { p_vote_id: string }
        Returns: Json
      }
      admin_get_syndic_charge_call_stats: {
        Args: { p_charge_call_id: string }
        Returns: Json
      }
      admin_publish_residence_vote: {
        Args: { p_vote_id: string }
        Returns: Json
      }
      admin_publish_syndic_charge_call: {
        Args: { p_charge_call_id: string }
        Returns: Json
      }
      admin_record_syndic_payment: {
        Args: {
          p_allocations: Json
          p_amount: number
          p_notes: string
          p_owner_account_id: string
          p_payment_date: string
          p_payment_method: string
          p_reference: string
        }
        Returns: Json
      }
      admin_reverse_syndic_payment: {
        Args: { p_payment_id: string; p_reason: string }
        Returns: Json
      }
      admin_validate_owner_submission: {
        Args: {
          p_code_hash: string
          p_expires_at: string
          p_submission_id: string
        }
        Returns: Json
      }
      complete_owner_activation: {
        Args: {
          p_activation_code_id: string
          p_auth_user_id: string
          p_owner_account_id: string
          p_phone_e164: string
        }
        Returns: Json
      }
      is_admin: { Args: never; Returns: boolean }
      owner_get_residence_vote_results: {
        Args: { p_vote_id: string }
        Returns: Json
      }
      owner_get_syndic_summary: { Args: never; Returns: Json }
      register_owner_with_session:
        | {
            Args: {
              p_consent?: boolean
              p_email?: string
              p_first_name: string
              p_last_name: string
              p_phone: string
              p_token_hash: string
              p_whatsapp?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_attendance: string
              p_availability: string[]
              p_consent: boolean
              p_email: string
              p_first_name: string
              p_last_name: string
              p_phone: string
              p_subject: string
              p_token_hash: string
              p_whatsapp: string
            }
            Returns: Json
          }
    }
    Enums: {
      [_ in never]: never
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
    Enums: {},
  },
} as const
