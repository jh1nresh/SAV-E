export type AccountDeletionDependencies = {
  deleteProfile(): Promise<void>;
  deletePrivyUser(): Promise<void>;
};

/**
 * Deletes owner-scoped Savvy data before deleting the external identity.
 *
 * If Privy is temporarily unavailable, the user can authenticate again and
 * retry; their Savvy profile and cascading private data are already gone. The
 * inverse order could strand private data after the identity becomes unable to
 * authenticate, so it is deliberately avoided.
 */
export async function deleteAccount(
  dependencies: AccountDeletionDependencies,
): Promise<void> {
  await dependencies.deleteProfile();
  await dependencies.deletePrivyUser();
}
