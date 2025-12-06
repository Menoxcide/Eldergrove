import { useCallback } from 'react';
import { parseError, ParsedError, formatErrorForDialog } from '@/lib/errorUtils';
import { useGameMessageStore } from '@/stores/useGameMessageStore';

export interface UseErrorHandlerReturn {
  handleError: (error: unknown, customMessage?: string) => ParsedError;
  showError: (title: string, message: string, details?: ParsedError['details'], suggestion?: string) => void;
}

/**
 * Extract Supabase error details for logging
 */
function extractSupabaseErrorDetails(error: unknown): Record<string, unknown> {
  if (error && typeof error === 'object') {
    const errorObj = error as Record<string, unknown>;
    return {
      message: errorObj.message || 'No message',
      details: errorObj.details || null,
      hint: errorObj.hint || null,
      code: errorObj.code || null,
    };
  }
  return { message: String(error) };
}

/**
 * Log error with proper formatting (only in development)
 */
function logError(parsedError: ParsedError, originalError: unknown): void {
  // Only log errors in development environment
  if (process.env.NODE_ENV === 'development') {
    console.error('=== Error Handled ===');
    console.error('Parsed Error:', JSON.stringify(parsedError, null, 2));

    // Extract Supabase-specific error details
    const supabaseDetails = extractSupabaseErrorDetails(originalError);
    if (supabaseDetails.details || supabaseDetails.hint || supabaseDetails.code) {
      console.error('Supabase Error Details:', JSON.stringify(supabaseDetails, null, 2));
    }

    // Log original error with full details
    if (originalError instanceof Error) {
      console.error('Original Error:', {
        name: originalError.name,
        message: originalError.message,
        stack: originalError.stack,
      });
    } else {
      console.error('Original Error:', JSON.stringify(originalError, null, 2));
    }
    console.error('===================');
  }
}

/**
 * Custom hook for handling errors with native dialogs
 */
export function useErrorHandler(): UseErrorHandlerReturn {
  const handleError = useCallback((error: unknown, customMessage?: string) => {
    const parsedError = parseError(error);
    
    // Override message if custom message provided
    if (customMessage) {
      parsedError.message = customMessage;
    }
    
    // Show error in game message system
    useGameMessageStore.getState().addMessage('error', formatErrorForDialog(parsedError));
    
    // Also log to console for debugging with proper formatting
    logError(parsedError, error);
    
    return parsedError;
  }, []);

  const showError = useCallback((title: string, message: string, details?: ParsedError['details'], suggestion?: string) => {
    const customError: ParsedError = {
      type: 'other',
      title,
      message,
      details,
      suggestion,
      icon: '⚠️',
    };
    
    useGameMessageStore.getState().addMessage('error', formatErrorForDialog(customError));
  }, []);

  return {
    handleError,
    showError,
  };
}

/**
 * Standalone function for use in stores (outside React components)
 */
export function handleError(error: unknown, customMessage?: string): ParsedError {
  const parsedError = parseError(error);
  
  // Override message if custom message provided
  if (customMessage) {
    parsedError.message = customMessage;
  }
  
  // Show error in game message system
  useGameMessageStore.getState().addMessage('error', formatErrorForDialog(parsedError));
  
  // Also log to console for debugging with proper formatting
  logError(parsedError, error);
  
  return parsedError;
}

/**
 * Standalone function for showing custom errors (outside React components)
 */
export function showError(title: string, message: string, details?: ParsedError['details'], suggestion?: string): void {
  const customError: ParsedError = {
    type: 'other',
    title,
    message,
    details,
    suggestion,
    icon: '⚠️',
  };
  
  useGameMessageStore.getState().addMessage('error', formatErrorForDialog(customError));
}

