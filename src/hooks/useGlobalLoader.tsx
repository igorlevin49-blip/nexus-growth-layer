import { useEffect } from "react";
import { useIsFetching, useIsMutating } from "@tanstack/react-query";
import { useLoader } from "@/contexts/LoaderContext";

/**
 * Hook to automatically show/hide global loader based on React Query state
 * Shows loader when there are pending queries or mutations
 */
export function useGlobalLoader() {
  const isFetching = useIsFetching();
  const isMutating = useIsMutating();
  const { showLoader, hideLoader } = useLoader();

  useEffect(() => {
    // Show loader if there are any fetching queries or mutating requests
    if (isFetching > 0 || isMutating > 0) {
      showLoader();
    } else {
      hideLoader();
    }
  }, [isFetching, isMutating, showLoader, hideLoader]);
}
