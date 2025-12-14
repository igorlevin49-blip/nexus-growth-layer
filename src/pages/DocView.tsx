import { useParams, Link } from 'react-router-dom';
import { useLegalDocument } from '@/hooks/useLegalDocuments';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ArrowLeft, Calendar } from 'lucide-react';
import { format } from 'date-fns';
import { ru } from 'date-fns/locale';
import { Helmet } from 'react-helmet';
import ReactMarkdown from 'react-markdown';

export default function DocView() {
  const { slug } = useParams<{ slug: string }>();
  const { data: document, isLoading, error } = useLegalDocument(slug!);

  if (isLoading) {
    return null;
  }

  if (error || !document) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <Card className="max-w-md">
          <CardContent className="pt-6 text-center">
            <h1 className="text-2xl font-bold mb-2">Документ не найден</h1>
            <p className="text-muted-foreground mb-4">
              Запрашиваемый документ не существует или не опубликован
            </p>
            <Link to="/docs">
              <Button>
                <ArrowLeft className="mr-2 h-4 w-4" />
                Вернуться к документам
              </Button>
            </Link>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <>
      <Helmet>
        <title>{document.meta_title || document.title}</title>
        <meta 
          name="description" 
          content={document.meta_description || document.summary || ''} 
        />
        <meta property="og:title" content={document.meta_title || document.title} />
        <meta 
          property="og:description" 
          content={document.meta_description || document.summary || ''} 
        />
        {document.og_image_url && (
          <meta property="og:image" content={document.og_image_url} />
        )}
      </Helmet>

      <div className="min-h-screen bg-background">
        <div className="container mx-auto px-4 py-8 max-w-4xl">
          <Link to="/docs">
            <Button variant="ghost" className="mb-6">
              <ArrowLeft className="mr-2 h-4 w-4" />
              Все документы
            </Button>
          </Link>

          <Card>
            <CardContent className="pt-6">
              <header className="mb-8">
                <h1 className="text-3xl font-bold mb-4">{document.title}</h1>
                {document.effective_at && (
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Calendar className="h-4 w-4" />
                    <span>
                      Вступает в силу: {format(new Date(document.effective_at), 'dd MMMM yyyy', { locale: ru })}
                    </span>
                  </div>
                )}
              </header>

              <article className="prose prose-neutral dark:prose-invert max-w-none">
                {'currentVersion' in document && document.currentVersion?.content_md ? (
                  <ReactMarkdown>{document.currentVersion.content_md}</ReactMarkdown>
                ) : (
                  <p className="text-muted-foreground">Содержание документа пока не добавлено</p>
                )}
              </article>
            </CardContent>
          </Card>
        </div>
      </div>
    </>
  );
}