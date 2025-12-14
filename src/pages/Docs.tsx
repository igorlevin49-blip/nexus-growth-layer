import { Link } from 'react-router-dom';
import { useLegalDocuments } from '@/hooks/useLegalDocuments';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { FileText, Calendar } from 'lucide-react';
import { format } from 'date-fns';
import { ru } from 'date-fns/locale';

export default function Docs() {
  const { data: documents, isLoading } = useLegalDocuments('ru');

  if (isLoading) {
    return null;
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 py-8 max-w-4xl">
        <div className="mb-8">
          <h1 className="text-3xl font-bold mb-2">Юридические документы</h1>
          <p className="text-muted-foreground">
            Правовые документы, регулирующие использование платформы
          </p>
        </div>

        {!documents || documents.length === 0 ? (
          <Card>
            <CardContent className="pt-6">
              <p className="text-center text-muted-foreground">
                Документы пока не опубликованы
              </p>
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-4">
            {documents.map((doc) => (
              <Link key={doc.id} to={`/docs/${doc.slug}`}>
                <Card className="hover:bg-accent/50 transition-colors cursor-pointer">
                  <CardHeader>
                    <div className="flex items-start gap-4">
                      <FileText className="h-6 w-6 text-primary mt-1" />
                      <div className="flex-1">
                        <CardTitle className="mb-2">{doc.title}</CardTitle>
                        {doc.summary && (
                          <CardDescription className="text-sm">
                            {doc.summary}
                          </CardDescription>
                        )}
                        {doc.effective_at && (
                          <div className="flex items-center gap-2 mt-3 text-sm text-muted-foreground">
                            <Calendar className="h-4 w-4" />
                            <span>
                              Вступает в силу: {format(new Date(doc.effective_at), 'dd MMMM yyyy', { locale: ru })}
                            </span>
                          </div>
                        )}
                      </div>
                    </div>
                  </CardHeader>
                </Card>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}