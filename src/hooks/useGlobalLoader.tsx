import { useEffect } from "react";
import { useIsFetching, useIsMutating } from "@tanstack/react-query";
import { useLoader } from "@/contexts/LoaderContext";

/**
 * Hook to automatically show/hide global loader based on React Query state
 * Shows global cup loader for BOTH fetching and mutations
 */
export function useGlobalLoader() {
  const isFetching = useIsFetching();
  const isMutating = useIsMutating();
  const { showLoader, hideLoader } = useLoader();

  useEffect(() => {
    // Show global cup loader for BOTH fetching and mutations
    if (isFetching > 0 || isMutating > 0) {
      showLoader();
    } else {
      hideLoader();
    }
  }, [isFetching, isMutating, showLoader, hideLoader]);
}
