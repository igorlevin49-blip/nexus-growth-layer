import { createContext, useContext, useState, useCallback, ReactNode } from "react";

interface LoaderContextType {
  isLoading: boolean;
  showLoader: () => void;
  hideLoader: () => void;
  disableAutoLoader: () => void;
  enableAutoLoader: () => void;
}

const LoaderContext = createContext<LoaderContextType | undefined>(undefined);

export function LoaderProvider({ children }: { children: ReactNode }) {
  const [isLoading, setIsLoading] = useState(false);
  const [autoLoaderEnabled, setAutoLoaderEnabled] = useState(true);

  const showLoader = useCallback(() => {
    if (autoLoaderEnabled) {
      setIsLoading(true);
    }
  }, [autoLoaderEnabled]);

  const hideLoader = useCallback(() => {
    setIsLoading(false);
  }, []);

  const disableAutoLoader = useCallback(() => {
    setAutoLoaderEnabled(false);
    setIsLoading(false);
  }, []);

  const enableAutoLoader = useCallback(() => {
    setAutoLoaderEnabled(true);
  }, []);

  return (
    <LoaderContext.Provider value={{ isLoading, showLoader, hideLoader, disableAutoLoader, enableAutoLoader }}>
      {children}
    </LoaderContext.Provider>
  );
}

export function useLoader() {
  const context = useContext(LoaderContext);
  if (context === undefined) {
    throw new Error("useLoader must be used within a LoaderProvider");
  }
  return context;
}
