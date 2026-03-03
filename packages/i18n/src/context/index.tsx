import React, { createContext } from "react";
// store
import { TranslationStore } from "../store";

// eslint-disable-next-line react-refresh/only-export-components
export const TranslationContext = createContext<TranslationStore | null>(null);

interface TranslationProviderProps {
  children: React.ReactNode;
}

/**
 * Provides the translation store to the application
 */
export function TranslationProvider({ children }: TranslationProviderProps) {
  const [store] = React.useState(() => new TranslationStore());

  return <TranslationContext.Provider value={store}>{children}</TranslationContext.Provider>;
}
