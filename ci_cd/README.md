<!-- Working as a team in repositories and code buckets -->

# Step 1. Ensure the local repository is up-to-date
git pull origin main

# Step 2. Create a new branch for your changes
git checkout -b feature/my-change

# Step 3. Make your changes to the code or documentation
git add -A
git commit -m "Describe change"

# Step 4. Push your changes to the remote repository
git push -u origin feature/my-change

# Step 5. Create a Pull Request (PR) when approved
#   Open a PR: feature/my-change -> main
#   Let CI run + review happen
#   Merge via PR (prefer "Squash and merge" or "Rebase and merge")
git checkout main
git pull origin main
git branch -d feature/my-change
#   optional cleanup
git push origin --delete feature/my-change   
